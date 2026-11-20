# Musterlösung Übung 000: Stack, Speichersegmente, Heap und Startup-Code

Alle Messwerte stammen aus dem Debug-Build (`cmake --preset debug`) in Renode 1.17
mit `gdb-multiarch`. Adressen können sich bei anderen Compiler-Versionen leicht
verschieben; die Zusammenhänge bleiben gleich.

Zu jedem Teil gibt es ein GDB-Skript in [gdb/](gdb/), das die Lösung vorführt.
Renode in Terminal 1 starten, dann in Terminal 2 (jeweils im Projekt-Hauptverzeichnis):

```sh
gdb-multiarch -x excercise-000/gdb/teil<N>.gdb build/debug/stm32f103rb-app
```

Die Skripte setzen die CPU zu Beginn selbst zurück, können also beliebig oft
hintereinander laufen. Danach bleibt GDB interaktiv.

---

## Teil 0: Aufwärmen

Demo: [gdb/teil0.gdb](gdb/teil0.gdb)

**0.1 Welche Zeile in `main` hat die erste Ausgabe in Terminal 1 verursacht?**

Die erste UART-Ausgabe kommt von Zeile 198:

```cpp
uart_write("STM32F103RB startup OK\r\n");
```

Davor ist die UART noch gar nicht eingerichtet (`uart_setup()` in Zeile 195).
Schon bei `clock_setup()` (Zeile 193) können in Terminal 1 Renode-Warnungen
erscheinen (`unimplemented register RCC:CFGR` …). Das sind aber Meldungen des
Emulators über Registerzugriffe, keine Ausgabe der Firmware.

**0.2 Wie oft mussten Sie `next` tippen, bis die LED zum ersten Mal umgeschaltet hat?**

Elfmal, gezählt ab dem Breakpoint auf der ersten Zeile von `main`:

| `next` Nr. | GDB steht danach auf Zeile | LED (`monitor sysbus.gpioPortA.led State`) |
| --- | --- | --- |
| 1–9 | 190 … 200 (Initialisierung, Ausgaben, `heap_demo()`) | `False` |
| 10 | 203 `gpio_toggle(kLedPort, kLedPin);` | `False` |
| 11 | 204 `uart_write("tick data=");` | **`True`** |

GDB zeigt immer die Zeile, die als **nächste** ausgeführt wird. Nach dem
10. `next` steht `gpio_toggle` also nur bereit; erst das 11. `next` führt sie aus.

**0.3 Wo stand die CPU, als Sie mit Ctrl+C angehalten haben (`bt`)? Warum vermutlich dort?**

Fast immer in der Warteschleife von `delay_ms`:

```text
#0  (anonymous namespace)::delay_ms (delay=500) at src/main.cpp:...
#1  main () at src/main.cpp:...
```

In 15 von 15 Stichproben stand die CPU dort, gelegentlich trifft man auch
`SysTick_Handler`. Grund: Das Programm verbringt praktisch seine gesamte Zeit
mit Warten. Ein Schleifendurchlauf (LED umschalten, eine UART-Zeile senden)
dauert nur Mikrosekunden, danach wartet `delay_ms(500)` eine halbe Sekunde.
Ein zufälliger Anhaltezeitpunkt landet deshalb mit großer Wahrscheinlichkeit
in dieser Schleife. Die Interrupt-Routine `SysTick_Handler` läuft nur einmal
pro Millisekunde für wenige Takte und wird daher selten getroffen.

> **Typische Falle:** Wer hier `next` tippt, wartet scheinbar ewig. Die
> Warteschleife `while (system_millis < target) {}` ist **eine** Quelltextzeile;
> `next` kommt erst zurück, wenn die Schleife verlassen wird. GDB erreicht das,
> indem es Instruktion für Instruktion steppt (bis zu ~24 Mio. Takte bei 48 MHz,
> jeder Schritt ein TCP-Roundtrip zu Renode). Abhilfe: `finish` (läuft frei bis
> zum Rücksprung nach `main`) oder Ctrl+C.

**0.4 Wie sieht der Zeitablauf aus: Läuft die CPU nur, wenn Sie einen Befehl eingeben?**

Ja. Solange GDB die CPU angehalten hat, steht in Renode die gesamte
emulierte Maschine still, einschließlich der **virtuellen Zeit**. Der
SysTick-Timer zählt nicht weiter, es kommen keine `tick`-Zeilen. Die CPU
läuft nur während `continue` (bis Breakpoint oder Ctrl+C) bzw. während eines
`next`/`step`/`finish` (bis zur nächsten Zeile). Deshalb dauert `delay_ms`
im Einzelschritt „ewig“: Jeder Schritt lässt nur wenige virtuelle
Mikrosekunden verstreichen, die Schleife wartet aber auf 500 Millisekunden.

---

## Teil 1: Bauen und die ELF-Datei untersuchen

Demo: [gdb/teil1.sh](gdb/teil1.sh) (reine Shell, kein GDB nötig)

**1.1 Was meldet `file` über die Architektur? Warum kann man die Datei nicht auf dem PC ausführen?**

```text
ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), statically linked, with debug_info, not stripped
```

- **ELF 32-bit:** 32-Bit-Programm, **LSB** = Little Endian.
- **ARM, EABI5:** Maschinencode für ARM (hier Cortex-M3, Thumb-Befehlssatz), nicht für x86-64.
- **statically linked:** Alle Bibliotheken (libopencm3, newlib) sind eingebunden, es gibt kein Betriebssystem, das etwas nachlädt.
- **with debug_info, not stripped:** Symbolnamen und Zeileninformationen sind enthalten, das braucht GDB.

Auf dem PC läuft die Datei nicht, weil der x86-Prozessor die ARM-Befehle nicht
versteht. Außerdem erwartet das Programm eine ganz andere Umgebung: Es liegt
ab `0x0800_0000` im Flash, greift direkt auf Peripherie-Register zu (RCC, GPIO,
USART) und hat kein Betriebssystem unter sich. Genau dafür gibt es den Emulator
Renode bzw. das echte Board.

**1.2 Segmentgrößen und Symbole:**

`size --format=sysv` (ohne Debug-Abschnitte; Adressen dort **dezimal**):

| Abschnitt | Größe (Byte) | Adresse (hex) | Speicher |
| --- | --- | --- | --- |
| `.isr_vector` | 236 | `0x0800_0000` | Flash |
| `.text` | 3396 | `0x0800_00EC` | Flash |
| `.data` | 344 | `0x2000_0000` | RAM (Startwerte im Flash) |
| `.bss` | 792 | `0x2000_0158` | RAM |
| `.noinit` | 0 | `0x2000_0470` | RAM |

Die Variablen aus `main.cpp` (`nm -C -S -n`):

```text
08000c2c 00000035 t (anonymous namespace)::kRodataBanner
20000000 00000004 d (anonymous namespace)::g_data_counter
20000174 00000004 b (anonymous namespace)::g_bss_counter
20000178 00000020 b (anonymous namespace)::g_bss_buffer
20000198 00000004 b (anonymous namespace)::system_millis
```

Alle Buchstaben sind klein, alle Symbole haben also internal linkage (anonymer
Namespace). `kRodataBanner` wird als `t` (Text) und nicht als `r` angezeigt,
weil die Konstante im Abschnitt `.text` gelandet ist (siehe 1.2a).

Warum ist `.data` 344 Byte groß, obwohl `main.cpp` nur 4 Byte (`g_data_counter`)
beisteuert? Den Rest bringen die Bibliotheken mit: libopencm3
(`rcc_ahb_frequency`, `rcc_apb1_frequency`, `rcc_apb2_frequency`) und vor
allem newlib (`_impure_data`, 320 Byte Verwaltungsstruktur der C-Bibliothek).
Ähnlich bei `.bss`: `__sf`, `__atexit0` usw. stammen aus newlib.

**1.2a Gibt es einen Abschnitt `.rodata`?**

Nein. Das Linker-Script sortiert `*(.rodata*)` in den Ausgabeabschnitt `.text` ein:

```ld
.text :
{
    ...
    *(.text*)
    *(.rodata*)
    ...
} > FLASH
```

Konstanten und String-Literale liegen damit im Flash direkt hinter dem Code,
z. B. `kRodataBanner` bei `0x0800_0C2C`.

**1.2b Bei welchem Abschnitt sind VMA und LMA verschieden? Warum?**

```text
Idx Name          Size      VMA       LMA       File off  Algn
  2 .data         00000158  20000000  08000e30  00020000  2**3
                  CONTENTS, ALLOC, LOAD, DATA
```

Bei **`.data`**: Zur Laufzeit liegen die Variablen im RAM (VMA `0x2000_0000`),
denn sie müssen veränderbar sein. Das RAM ist nach dem Einschalten aber leer.
Die Startwerte (z. B. `0x12345678`) müssen daher dauerhaft im Flash
gespeichert sein: LMA `0x0800_0E30`, direkt hinter `.text` (`_etext`). Der
Startup-Code kopiert sie beim Reset von LMA nach VMA (`_sidata` → `_sdata`).

`objdump -h` zeigt auch bei `.bss` und `.noinit` eine Flash-LMA. Die ist
bedeutungslos: Beide Abschnitte haben kein `CONTENTS`, es wird also nichts
gespeichert und nichts kopiert. `.bss` wird vom Startup-Code nur genullt.

**1.3 Die Vektortabelle:**

```text
Contents of section .isr_vector:
 8000000 00500020 1d060008 7d060008 7d060008  .P. ....}...}...
```

| Wort | Bytes im Speicher | Wert (Little Endian) | Bedeutung |
| --- | --- | --- | --- |
| 0 | `00 50 00 20` | `0x2000_5000` | initialer Stack Pointer = `_estack` |
| 1 | `1d 06 00 08` | `0x0800_061D` | Reset-Handler, Bit 0 = Thumb |
| 2, 3 | `7d 06 00 08` | `0x0800_067D` | NMI/HardFault → `Default_Handler` |

- **Stack-Start:** `0x2000_0000 + 20 KiB = 0x2000_0000 + 0x5000 = 0x2000_5000`.
  Das ist genau das Ende des RAMs, also die erste Adresse **hinter** dem RAM.
  Das passt, weil der Cortex-M einen *full descending* Stack hat: Bei `push`
  wird SP zuerst um 4 verringert und dann geschrieben. Das erste Wort landet
  also bei `0x2000_4FFC`, der letzten gültigen RAM-Adresse.
- **Reset-Handler:** `0x0800_061D - 1 = 0x0800_061C`. `nm` bestätigt
  `0800061c T Reset_Handler`. Das gesetzte Bit 0 kennzeichnet den Thumb-Modus.
  Würde es fehlen, löste die CPU beim Reset sofort einen HardFault aus.

---

## Teil 2: Renode starten

Demo:

- Terminal 1: `renode --disable-xwt --console excercise-000/gdb/teil2.resc`
  ([gdb/teil2.resc](gdb/teil2.resc), lädt `renode/nucleo.resc` und fragt PC/SP ab)
- Terminal 2: `gdb-multiarch -x excercise-000/gdb/teil2.gdb build/debug/stm32f103rb-app`
  ([gdb/teil2.gdb](gdb/teil2.gdb), vergleicht die Register mit der Vektortabelle)

**2.1 Welchen Wert haben PC und SP direkt nach dem Start? Vergleich mit der Vektortabelle.**

Das hängt davon ab, *wann* man fragt.

**Im Renode-Monitor direkt nach dem Laden des Scripts** (wie in 2.3 beschrieben):

```text
(nucleo) sysbus.cpu PC
0x0
(nucleo) sysbus.cpu SP
0x0
```

Beide Register sind noch `0x0`. Das Script lädt zwar das ELF, ruft aber kein
`start` auf. Renode übernimmt die Werte aus der Vektortabelle erst in dem
Moment, in dem die Maschine startet. Beim Verbinden mit GDB erscheint in
Terminal 1:

```text
cpu: Guessing VectorTableOffset value to be 0x8000000.
cpu: Setting initial values: PC = 0x800061D, SP = 0x20005000.
nucleo: Machine started.
```

**Nach dem Verbinden mit GDB** (`target remote localhost:3333`):

| | Vektortabelle (Teil 1.3) | Register |
| --- | --- | --- |
| SP | Wort 0 = `0x2000_5000` | `sp = 0x2000_5000` |
| PC | Wort 1 = `0x0800_061D` | `pc = 0x0800_061C` (`Reset_Handler`) |

- **SP** stimmt exakt mit Wort 0 überein: das Ende des RAMs.
- **PC** ist um **1 kleiner** als Wort 1. Das ist das Thumb-Bit: Bit 0 des
  Reset-Vektors wird nicht in den PC übernommen (Befehle liegen immer an
  geraden Adressen), sondern landet im **T-Bit des xPSR** (Bit 24). GDB zeigt
  `xpsr = 0x41000000`, Bit 24 ist gesetzt, die CPU läuft im Thumb-Modus.
  Der Cortex-M kann nur Thumb; ein Reset-Vektor mit Bit 0 = 0 würde sofort
  einen HardFault auslösen.

Fazit: Die CPU macht beim Reset genau zwei Dinge, bevor sie den ersten Befehl
ausführt: `SP ← Wort 0`, `PC ← Wort 1` (Thumb-Bit → xPSR). Alles Weitere
erledigt der Software-Startup-Code im `Reset_Handler` (Teil 5).

---

## Teil 3: GDB verbinden und die wichtigsten Befehle

Demo: [gdb/teil3.gdb](gdb/teil3.gdb) (führt 3.1–3.6 einmal komplett vor)

**3.1 Stimmen `sp` und `pc` mit der Vektortabelle überein? Warum hat `pc` kein Thumb-Bit?**

```text
sp             0x20005000          0x20005000
pc             0x800061c           0x800061c <Reset_Handler>
xpsr           0x41000000          1090519040
0x8000000 <interrupt_vector>:   0x20005000      0x0800061d
```

- `sp` = Wort 0 = `0x2000_5000`: stimmt exakt.
- `pc` = `0x0800_061C`, Wort 1 = `0x0800_061D`: Der PC ist um 1 kleiner.

Thumb-Befehle sind 2 oder 4 Byte lang und liegen immer an **geraden**
Adressen; Bit 0 des PC ist deshalb immer 0 und trägt keine Information. In
Sprungzielen (Vektortabelle, `bx`, `blx`, Funktionszeiger) verwendet ARM
Bit 0 stattdessen als Kennzeichen „Ziel ist Thumb-Code“. Beim Laden des
Reset-Vektors übernimmt die CPU Bit 0 in das **T-Bit des xPSR** (Bit 24,
`0x0100_0000`, hier gesetzt) und löscht es im PC. Siehe auch Teil 2.1.

> **Achtung, Falle beim Nachvollziehen:** Wer GDB nach einem
> `monitor sysbus.cpu Reset` direkt `continue` schickt, während die CPU
> schon auf `Reset_Handler` steht und dort ein Breakpoint sitzt, kann die
> Verbindung verlieren (`Remote connection closed`). GDB hat den alten PC
> noch im Cache und versucht, den Breakpoint per Einzelschritt zu
> überspringen. Abhilfe: nach dem Reset `maintenance flush register-cache`
> (bzw. `flushregs`). Die Demo-Skripte machen das.

**Aufgabe 3: `break main`, `continue`, einige `next`, mindestens zwei Variablen lesen**

Ausschnitt aus der Demo (Halt in `main`, nach den Zeilen 189–191 und `clock_setup()`/`gpio_setup()`):

```text
(gdb) print g_data_counter
$1 = 305419897
(gdb) print/x g_data_counter
$2 = 0x12345679
(gdb) print &g_data_counter
$3 = (uint32_t *) 0x20000000 <(anonymous namespace)::g_data_counter>
(gdb) print g_bss_counter
$4 = 1
(gdb) ptype g_bss_buffer
type = unsigned char [32]
(gdb) print/x *g_bss_buffer@4
$5 = {0x42, 0x0, 0x0, 0x0}
(gdb) print kRodataBanner
$6 = "Memory layout demo (.data/.bss/.rodata/stack/heap)\r\n"
(gdb) set var g_bss_counter = 5
(gdb) print g_bss_counter
$7 = 5
```

- `g_data_counter` ist `0x12345679`: Startwert `0x12345678` aus `.data`,
  Zeile 190 hat schon einmal `+1` gerechnet.
- `g_bss_counter` ist `1`: aus `.bss` mit `0` gestartet, Zeile 189 hat `+1` gerechnet.
- `g_bss_buffer[0]` ist `0x42` (Zeile 191), der Rest ist noch `0`.
- `set var` schreibt wirklich in das RAM des Targets. Die nächste
  `tick`-Zeile zeigt danach `bss=5` statt `bss=1` (ausgegeben wird vor dem Erhöhen).

> **Hinweis zu `x/s kRodataBanner` (Beispiel in 3.2):** Auf diesem Stand
> der Aufgabe meldet GDB `evaluation of this expression requires the program
> to have a function "malloc"`. GCC beschreibt die Konstante in den
> Debug-Infos nur über ihren **Wert** (`DW_AT_const_value`), nicht über ihre
> Adresse. `print kRodataBanner` funktioniert deshalb, `x/s` und
> `info symbol` nicht. Die Adresse erfährt man trotzdem über `nm`
> (`0x08000c2c`) oder die UART-Ausgabe; dann klappt `x/s 0x08000c2c`.
> Auf `main` ist das inzwischen behoben (`extern`-Deklaration in `main.cpp`).

**3.5 `backtrace` und `info frame`** (Halt in `uart_setup`):

```text
#0  (anonymous namespace)::uart_setup () at src/main.cpp:70
#1  0x0800059a in main () at src/main.cpp:195
Stack level 0, frame at 0x20004fe8:
 pc = 0x8000200 in (anonymous namespace)::uart_setup (src/main.cpp:70); saved pc = 0x800059a
 Saved registers:
  r7 at 0x20004fe0, lr at 0x20004fe4
```

`saved pc = 0x800059a` ist die Rücksprungadresse in `main` (direkt hinter dem
`bl uart_setup`). Sie wurde als `lr` bei `0x2000_4FE4` auf den Stack gelegt.
Die Warnung `unable to determine sp alias, assuming msp` ist harmlos: Renode
meldet das Register `CONTROL` nicht, GDB nimmt korrekt den Main Stack Pointer an.

**Optional: Meldungen in `/tmp/usart2.log`** (identisch mit der Ausgabe in Terminal 1):

```text
STM32F103RB startup OK
Memory layout demo (.data/.bss/.rodata/stack/heap)
&g_data_counter (.data): 0x20000000
&g_bss_counter (.bss): 0x20000174
kRodataBanner (.rodata): 0x08000C2C
&stack_probe (stack): 0x20004FD0
_sdata: 0x20000000
_edata: 0x20000158
_sbss: 0x20000158
_ebss: 0x20000470
_heap_start: 0x20000470
_heap_end / _stack_limit: 0x20004800
_stack_top: 0x20005000
.data bytes: 344
.bss bytes: 792
heap capacity bytes: 17296
heap alloc 64 bytes at 0x20000470
tick data=0x12345679 bss=1
tick data=0x1234567A bss=2
...
```

Die Firmware gibt damit selbst schon die wichtigsten Adressen aus. Die Teile
4–7 weisen sie mit GDB nach.

---

## Teil 4: Wo liegt was?

Demo: [gdb/teil4.gdb](gdb/teil4.gdb) (gibt alle Werte für die Tabelle aus)

**4.1 `info symbol`** (Halt in `main`):

```text
(gdb) info symbol &g_data_counter
(anonymous namespace)::g_data_counter in section .data
(gdb) info symbol &g_bss_counter
(anonymous namespace)::g_bss_counter in section .bss
(gdb) info symbol &g_bss_buffer
(anonymous namespace)::g_bss_buffer in section .bss
(gdb) info address main
Symbol "main()" is a function at address 0x8000570.
```

> **`info symbol kRodataBanner` auf diesem Stand:** GDB meldet
> `evaluation of this expression requires the program to have a function "malloc"`.
> Grund (siehe Teil 3): In den DWARF-Debug-Infos steht für `kRodataBanner` nur
> der **Wert**, keine Adresse. Die **ELF-Symboltabelle** kennt die Adresse aber,
> und die liest `nm`:
>
> ```text
> (gdb) shell arm-none-eabi-nm -C build/debug/stm32f103rb-app | grep kRodataBanner
> 08000c2c t (anonymous namespace)::kRodataBanner
> (gdb) info symbol 0x08000c2c
> (anonymous namespace)::kRodataBanner in section .text
> (gdb) x/s 0x08000c2c
> 0x8000c2c <...kRodataBanner...>: "Memory layout demo (.data/.bss/.rodata/stack/heap)\r\n"
> ```
>
> | Quelle | gelesen von | Inhalt für `kRodataBanner` |
> | --- | --- | --- |
> | ELF-Symboltabelle (`.symtab`) | `nm`, `info symbol <adresse>` | Name + Adresse |
> | DWARF (`.debug_info`) | `print`, `x`, `info symbol <name>` | Name + Typ + Wert, **keine** Adresse |
>
> Auf `main` ist das behoben; dort funktioniert `info symbol kRodataBanner` direkt.

**4.2 Tabelle:**

| Variable | Adresse | Flash oder RAM? | Segment |
| --- | --- | --- | --- |
| `g_data_counter` | `0x2000_0000` | RAM | `.data` |
| `g_bss_counter` | `0x2000_0174` | RAM | `.bss` |
| `g_bss_buffer` | `0x2000_0178` (32 Byte) | RAM | `.bss` |
| String aus `kRodataBanner` | `0x0800_0C2C` (53 Byte) | Flash | `.rodata` (Abschnitt laut GDB: **`.text`**) |
| Funktion `main` | `0x0800_0570` | Flash | `.text` |
| lokale Variable `stack_probe` in `print_memory_layout()` | `0x2000_4FD0` | RAM | Stack |
| statische Variable `current_heap_end` in `_sbrk()` | `0x2000_019C` | RAM | `.bss` |

Erläuterungen:

- **`main`:** `info address main` liefert `0x0800_0570`, `break main` hält aber
  bei `0x0800_0574`. GDB setzt den Breakpoint hinter den **Prolog** der
  Funktion (`push {r7, lr}`, Frame-Pointer setzen), damit lokale Variablen
  beim Halt schon gültig sind. `break *main` hielte genau bei `0x0800_0570`.
- **`stack_probe`:** `print &stack_probe` (Halt in `print_memory_layout`)
  ergibt `0x2000_4FD0`, also knapp unterhalb von `_stack_top` = `0x2000_5000`.
  `info symbol &stack_probe` meldet `No symbol matches`: Lokale Variablen
  haben **kein Symbol** in der ELF-Datei. Ihre Adresse entsteht erst zur
  Laufzeit relativ zum Stack Pointer und hängt davon ab, wer die Funktion
  aufruft. Die Firmware gibt denselben Wert per UART aus
  (`&stack_probe (stack): 0x20004FD0`).
- **`current_heap_end`:** Die Variable ist `static` **innerhalb** der Funktion
  `_sbrk`, also nur dort sichtbar, aber trotzdem eine **globale Lebensdauer**:
  Sie liegt in `.bss` (`current_heap_end in section .bss`), nicht auf dem
  Stack. Sie ist mit `0` initialisiert, deshalb `.bss` und nicht `.data`.
  `nm` zeigt sie als `current_heap_end.0`; der Zusatz `.0` unterscheidet
  gleichnamige statische Variablen verschiedener Funktionen.

**4.1 An welcher Adresse beginnt `.data`, und wo endet `.bss`?**

```text
(gdb) print &_sdata     -> 0x20000000
(gdb) print &_edata     -> 0x20000158
(gdb) print &_sbss      -> 0x20000158
(gdb) print &_ebss      -> 0x20000470
```

`.data` beginnt bei `0x2000_0000` (ganz am Anfang des RAMs) und ist
`0x158` = 344 Byte groß. `.bss` schließt direkt an und **endet bei
`0x2000_0470`** (exklusiv; 792 Byte). `info files` bestätigt die Bereiche:

```text
0x08000000 - 0x080000ec is .isr_vector
0x080000ec - 0x08000e30 is .text
0x20000000 - 0x20000158 is .data
0x20000158 - 0x20000470 is .bss
0x20000470 - 0x20000470 is .noinit
```

Direkt dahinter beginnt der Heap (`_heap_start` = `0x2000_0470`, Teil 7).

**4.2 Warum liegen `.data` und `.bss` im RAM, Konstanten und Code im Flash?**

- **Flash** ist nicht flüchtig (der Inhalt bleibt ohne Strom erhalten), kann
  aber im laufenden Betrieb nicht einfach beschrieben werden. Ideal für
  alles, was sich **nie ändert**: Maschinencode, Konstanten, die
  Vektortabelle und die **Startwerte** von `.data`.
- **RAM** ist schnell beschreibbar, verliert seinen Inhalt aber ohne Strom.
  Variablen **müssen sich ändern** können, deshalb liegen `.data` und `.bss`
  im RAM. Weil das RAM nach dem Einschalten undefiniert ist, muss der
  Startup-Code es vorbereiten: `.data` aus dem Flash kopieren, `.bss` nullen
  (Teil 5).

Auf dem Cortex-M3 kann die CPU Code und Konstanten direkt aus dem Flash
lesen und ausführen („execute in place“). Es ist also nicht nötig, das
Programm vorher ins RAM zu laden wie auf dem PC.

**4.3 Wo ist `.rodata` geblieben?**

```text
$ arm-none-eabi-size --format=sysv build/debug/CMakeFiles/stm32f103rb-app.dir/src/main.cpp.o
section                                          size   addr
.data                                               0      0
.bss                                                0      0
.rodata._ZN12_GLOBAL__N_1L8kLedPortE                4      0
.rodata._ZN12_GLOBAL__N_1L7kLedPinE                 2      0
...
.data._ZN12_GLOBAL__N_114g_data_counterE            4      0
.bss._ZN12_GLOBAL__N_113g_bss_counterE              4      0
.bss._ZN12_GLOBAL__N_112g_bss_bufferE              32      0
.rodata._ZN12_GLOBAL__N_1L13kRodataBannerE         53      0
.bss._ZN12_GLOBAL__N_113system_millisE              4      0
.rodata                                           362      0
.text.main                                        172      0
...
```

- **4.3a** Die Objektdatei hat noch getrennte Abschnitte `.text.*`, `.rodata*`,
  `.data.*` und `.bss.*`. Wegen `-ffunction-sections -fdata-sections` bekommt
  **jede Funktion und jede Variable einen eigenen Abschnitt** (Name =
  mangled Symbolname). Der Banner-Text steht in
  `.rodata._ZN12_GLOBAL__N_1L13kRodataBannerE` (53 Byte = 50 Textzeichen +
  `\r\n` (2) + abschließendes `\0` (1)). Der namenlose Abschnitt `.rodata` (362 Byte) enthält die
  String-Literale aus den `uart_write("…")`-Aufrufen. Die Adressen sind alle
  `0`: Erst der Linker legt die endgültigen Adressen fest. Die vielen kleinen
  Abschnitte erlauben ihm, mit `--gc-sections` alles Unbenutzte wegzulassen.
- **4.3b** Für die Hardware ist es egal: Beide landen im Flash, werden nur
  gelesen und nie verändert. Die CPU unterscheidet beim Lesen nicht, ob ein
  Byte zu „Code“ oder zu „Konstanten“ gehört; es sind Adressen im Flash.
- **4.3c** Ein getrennter `.rodata`-Abschnitt hilft trotzdem:
  - **Übersicht:** `size` und Map-Datei zeigen getrennt, wie viel Flash Code
    und wie viel Konstanten (Tabellen, Texte) belegen.
  - **Speicherbereiche:** Man kann Konstanten gezielt woanders hinlegen
    (z. B. externes Flash, eigener Bereich für Kalibrierdaten).
  - **Speicherschutz:** Mit einer MPU lässt sich `.rodata` als „lesen ja,
    ausführen nein“ (Execute Never) markieren. Daten, die versehentlich oder
    böswillig angesprungen werden, lösen dann einen Fault aus.
  - **Analyse-Werkzeuge:** `nm` zeigt Konstanten dann mit `r` statt `t`, der
    Debugger meldet `in section .rodata` statt `.text`.
