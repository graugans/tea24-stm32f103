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

---

## Teil 5: Der Startup-Code

Demo: [gdb/teil5.gdb](gdb/teil5.gdb)

> **Stolperstein `print &_sdata`:** Das funktioniert nur, wenn die CPU in
> C-Code steht (z. B. `Reset_Handler`, `_sbrk`). Steht sie in `main.cpp`,
> meldet GDB `Missing ELF symbol "(anonymous namespace)::_sdata"`: `main.cpp`
> deklariert `_sdata` & Co. per `extern "C"` **innerhalb** des anonymen
> Namespace, und GDB sucht dann zuerst dort. Das Skript hält deshalb gleich
> zu Beginn auf `*Reset_Handler`.

**5.2 Linker-Symbole:**

```text
$ arm-none-eabi-nm -n build/debug/stm32f103rb-app | grep ...
00000800 A _Min_Stack_Size
08000e30 A _sidata
20000000 D _sdata
20000158 D _edata
20000158 B _sbss
20000470 B _ebss
20000470 B _end
20000470 B _heap_start
20004800 A _heap_end
20004800 B _stack_limit
20005000 A _estack
20005000 R _stack_top
```

| Symbol | Wert | Bedeutung |
| --- | --- | --- |
| `_sidata` | `0x0800_0E30` | Startwerte von `.data` im Flash (direkt hinter `.text`) |
| `_sdata` / `_edata` | `0x2000_0000` / `0x2000_0158` | `.data` im RAM |
| `_sbss` / `_ebss` | `0x2000_0158` / `0x2000_0470` | `.bss` im RAM |
| `_end` = `_heap_start` | `0x2000_0470` | Anfang des Heaps |
| `_heap_end` = `_stack_limit` | `0x2000_4800` | `_stack_top - 0x800` |
| `_estack` = `_stack_top` | `0x2000_5000` | Ende des RAMs, Start-SP |

Das `A` bei `_Min_Stack_Size`, `_sidata`, `_heap_end` und `_estack` heißt
„absolut“: Diese Symbole sind im Linker-Script **berechnet** und gehören zu
keinem Abschnitt. `_Min_Stack_Size` ist gar keine Adresse, sondern eine Zahl
(`0x800`), die als Symbol verkleidet ist.

**Aufgabe 5.2 Größen:**

```text
(gdb) print (char*)&_edata - (char*)&_sdata   -> 344
(gdb) print (char*)&_ebss  - (char*)&_sbss    -> 792
$ arm-none-eabi-size --format=sysv build/debug/stm32f103rb-app
.data                344   536870912
.bss                 792   536871256
```

`.data` = `0x158` = 344 Byte, `.bss` = `0x318` = 792 Byte. Beides stimmt
exakt mit `size` überein. (`536870912` ist `0x2000_0000` in Dezimal.) Der
Cast auf `char*` ist nötig, weil die Symbole im Startup-Code als `uint32_t`
deklariert sind: `&_edata - &_sdata` ergäbe sonst die Anzahl der **Wörter**
(86), nicht der Bytes.

**5.3 Reset-Handler im Quelltext:**

- **Zwei Schleifen:**
  1. `while (dst < &_edata) *dst++ = *src++;` kopiert ab `_sidata` (Flash)
     nach `_sdata` bis `_edata` (RAM), also die Startwerte von `.data`.
  2. `while (dst < &_ebss) *dst++ = 0;` füllt `_sbss` bis `_ebss` mit Nullen.
- **Wörter statt Bytes:** Ein Wort (4 Byte) pro Schleifendurchlauf heißt
  viermal weniger Durchläufe. Der Cortex-M3 kopiert ein Wort mit einem
  einzigen `ldr`/`str` genauso schnell wie ein Byte. Das geht nur, weil
  `. = ALIGN(4);` **vor und hinter** `.data` und `.bss` im Linker-Script
  steht: Anfang und Ende liegen dann garantiert auf einer durch 4 teilbaren
  Adresse. Die Schleife trifft `_edata` bzw. `_ebss` exakt, schreibt also
  kein Byte zu viel und vergisst keines.
- **`__libc_init_array()`** ruft alle Funktionszeiger aus
  `.preinit_array`, `_init()` und `.init_array` auf. Dort trägt der Compiler
  die **Konstruktoren globaler C++-Objekte** ein (Bonus 1). In diesem Build
  stehen dort nur zwei Einträge der C-Bibliothek:

  ```text
  (gdb) x/2a &__init_array_start
  0x8000e24: 0x8000bb9 <register_fini>  0x800016d <frame_dummy>
  ```

  (`register_fini` meldet die Destruktoren für `exit()` an, `frame_dummy`
  stammt aus `crtstuff.c` der Toolchain. Die ungeraden Adressen sind das
  Thumb-Bit, siehe Teil 1.3.)

  Der Aufruf **muss nach** dem Kopieren und Nullen stehen: Ein Konstruktor
  darf globale Variablen lesen und beschreiben. Liefe er vorher, würde er
  Müll lesen, und seine Ergebnisse in `.bss` würden vom Nullen gleich wieder
  überschrieben.
- **Wenn `main` zurückkehrt:** Die CPU landet in `while (1) {}` am Ende von
  `Reset_Handler` (`0x0800_0664: nop; b.n 0x8000664`). Es gibt kein
  Betriebssystem, an das man zurückkehren könnte. Die Schleife verhindert,
  dass die CPU in beliebigen Flash-Inhalt hinter der Funktion weiterläuft.
- **`Default_Handler`** ist ebenfalls nur eine Endlosschleife. Alle
  `*_Handler`/`*_IRQHandler` sind mit
  `__attribute__((weak, alias("Default_Handler")))` deklariert:
  - `alias`: Der Name ist nur ein zweiter Name für dieselbe Funktion, also
    dieselbe Adresse.
  - `weak`: Definiert eine andere Datei eine Funktion mit **demselben Namen**
    (eine „starke“ Definition), nimmt der Linker diese und verwirft den Alias.
    Gibt es keine, bleibt der Alias auf `Default_Handler`.

  Tritt ein Interrupt ohne eigenen Handler auf, springt die CPU in
  `Default_Handler` und **hängt dort für immer**. Kein Absturz, keine
  Meldung, das Programm steht einfach. In GDB erkennt man das an
  `info symbol $pc` → `Default_Handler`. Welche Exception es war, steht in
  den unteren 9 Bit von xPSR: `print $xpsr & 0x1ff` (Exception-Nummer,
  z. B. 3 = HardFault, 15 = SysTick, ab 16 = IRQ 0, 1, …).

**5.3 Reset-Handler im Maschinencode** (`disassemble /s Reset_Handler`,
gekürzt):

```text
136     {
=> 0x0800061c <+0>:     push    {r7, lr}
   0x0800061e <+2>:     sub     sp, #8
   0x08000620 <+4>:     add     r7, sp, #0
138         uint32_t *src = &_sidata;
   0x08000622 <+6>:     ldr     r3, [pc, #68]   @ (0x8000668 <Reset_Handler+76>)
   0x08000624 <+8>:     str     r3, [r7, #4]
...
142             *dst++ = *src++;
   0x08000638 <+28>:    ldr     r2, [r2, #0]
   0x0800063a <+30>:    str     r2, [r3, #0]
141         while (dst < &_edata) {
   0x0800063c <+32>:    ldr     r3, [r7, #0]
   0x0800063e <+34>:    ldr     r2, [pc, #48]   @ (0x8000670 <Reset_Handler+84>)
   0x08000640 <+36>:    cmp     r3, r2
   0x08000642 <+38>:    bcc.n   0x800062c <Reset_Handler+16>
...
152         __libc_init_array();
   0x0800065c <+64>:    bl      0x8000b68 <__libc_init_array>
155         (void)main();
   0x08000660 <+68>:    bl      0x8000570 <main()>
157         while (1) {
   0x08000664 <+72>:    nop
   0x08000666 <+74>:    b.n     0x8000664 <Reset_Handler+72>
   0x08000668 <+76>:    lsrs    r0, r6, #24      <- keine Befehle!
   ...
```

Beobachtungen:

- **Erste Instruktion `push {r7, lr}`:** Der Reset-Handler benutzt sofort den
  Stack. Das geht nur, weil die **Hardware** den SP schon vor der ersten
  Instruktion aus Wort 0 der Vektortabelle geladen hat (`sp = 0x20005000`).
- **Debug-Build:** `src` und `dst` liegen nicht in Registern, sondern im
  Stack-Frame (`[r7, #4]`, `[r7, #0]`). Jeder Durchlauf lädt und speichert sie
  neu. Mit `-O2` wären es ein paar Register-Befehle.
- **Schleife „rückwärts“:** `b.n` springt zuerst zur Bedingung (`+32`), der
  Rumpf (`+16` … `+30`) steht davor. `bcc` („branch if carry clear“) ist der
  vorzeichenlose Vergleich `dst < &_edata`.
- **Literal-Pool:** Ab `+76` stehen keine Befehle, sondern Daten. Ein
  Thumb-Befehl kann keine 32-Bit-Konstante enthalten, deshalb legt der
  Compiler die Adressen hinter die Funktion und lädt sie mit
  `ldr r3, [pc, #68]`. Der Disassembler versucht sie trotzdem als Befehle zu
  lesen (`lsrs r0, r6, #24`). Als Daten betrachtet sind es genau die
  Linker-Symbole:

  ```text
  (gdb) x/5wx (char*)Reset_Handler + 76
  0x8000668 <Reset_Handler+76>: 0x08000e30      0x20000000      0x20000158      0x20000158
  0x8000678 <Reset_Handler+92>: 0x20000470
                                _sidata     _sdata      _edata      _sbss       _ebss
  ```

**5.4 Experiment.** Nach `monitor sysbus.cpu Reset` steht die CPU auf der
ersten Instruktion:

```text
sp             0x20005000          0x20005000
pc             0x800061c           0x800061c <Reset_Handler>
Reset_Handler in section .text

(gdb) x/wx $pdata
0x20000000 <..g_data_counterE>: 0x1234567e      <- Rest vom vorherigen Lauf
(gdb) x/wx $pbss
0x20000174 <..g_bss_counterE>:  0x00000006      <- Rest vom vorherigen Lauf
(gdb) set var *$pbss = 0xDEADBEEF
(gdb) x/wx &_sidata
0x8000e30:      0x12345678                       <- Startwert im Flash
```

Direkt nach dem Start von Renode sind beide Werte `0`; nach jedem weiteren
Reset steht dort, was der vorige Lauf hinterlassen hat (hier hatte `main`
schon einige Male gezählt). Damit der Watchpoint den Kopiervorgang sicher
sieht, setzt das Skript `g_data_counter` vorher noch auf `0`.

```text
(gdb) watch *$pdata
(gdb) continue
Hardware watchpoint 2: *$pdata
Old value = 0
New value = 305419896                        <- 0x12345678
Reset_Handler () at .../startup_stm32f103rb.c:141
141         while (dst < &_edata) {
(gdb) x/i $pc
=> 0x800063c <Reset_Handler+32>:        ldr     r3, [r7, #0]

(gdb) watch *$pbss
(gdb) continue
Old value = 3735928559                       <- 0xDEADBEEF
New value = 0
Reset_Handler () at .../startup_stm32f103rb.c:147
147         while (dst < &_ebss) {

(gdb) tbreak main
(gdb) continue
(gdb) print/x *$pdata   -> 0x12345678
(gdb) print/x *$pbss    -> 0x0
```

**Fragen:**

- **5.1** Direkt nach dem Reset: `0x1234_567E` (Rest vom vorigen Lauf; nach
  frischem Renode-Start `0`). Bei `main`: `0x1234_5678`. Der Startwert steht
  im **Flash** an `_sidata` = `0x0800_0E30` (LMA von `.data`) und wird von
  der ersten Schleife ins RAM kopiert. Er ist das **erste** Wort, weil
  `g_data_counter` die erste Variable in `.data` ist (`0x2000_0000`).
- **5.2** `g_bss_counter` ist `0`, obwohl `0xDEADBEEF` darin stand. Genullt
  hat ihn die **zweite Schleife** in `Reset_Handler` (`*dst++ = 0;`,
  Zeile 148). Das ist die Garantie von C/C++ „globale Variablen ohne
  Initialwert sind 0“. Sie gilt also nur, weil der Startup-Code sie
  einlöst.
- **5.3** Beide Watchpoints halten in `Reset_Handler`, wie erwartet. GDB
  meldet Zeile 141 bzw. 147 (die Schleifenbedingung), geschrieben hat aber
  die Zeile **davor**: `*dst++ = *src++;` (142) bzw. `*dst++ = 0;` (148).
  Grund: Ein Hardware-Watchpoint meldet sich **nach** dem schreibenden
  Befehl (`str r2, [r3, #0]` bei `+30`). Der PC zeigt dann schon auf den
  nächsten Befehl (`+32`), und der gehört zur Schleifenbedingung.
  `bt` zeigt nur `#0 Reset_Handler`: Es gibt noch keinen Aufrufer, die
  Hardware selbst hat hierher gesprungen.
- **5.4** `_edata - _sdata` = 344 Byte = **86 Wörter**. Davon gehört nur
  **ein** Wort uns:

  ```text
  20000000 00000004 d (anonymous namespace)::g_data_counter
  20000004 00000004 D rcc_ahb_frequency      <- libopencm3
  20000008 00000004 D rcc_apb2_frequency     <- libopencm3
  2000000c 00000004 D rcc_apb1_frequency     <- libopencm3
  20000010 00000004 D _impure_ptr            <- newlib
  20000018 00000140 D _impure_data           <- newlib, 320 Byte
  ```

  (`0x2000_0014` bis `0x2000_0017` ist eine Lücke, weil `_impure_data` auf
  8 Byte ausgerichtet ist.) Den Löwenanteil belegt `_impure_data`: die
  `struct _reent` von newlib mit `errno`, den `stdio`-Zeigern usw.
  
  `.data` ist so klein, weil dort nur Variablen landen, die **veränderbar**
  sind **und** einen Startwert **ungleich 0** haben. Konstanten gehen nach
  `.rodata` (Flash), mit 0 initialisierte Variablen nach `.bss` (kostet
  keinen Flash). `.data` ist das teuerste Segment: Es belegt **RAM und
  Flash** (für die Startwerte) und kostet beim Start Kopierzeit. Deshalb
  lohnt es sich, Startwerte nur zu vergeben, wo sie wirklich nötig sind.
- **5.5** `main.cpp` überschreibt **`SysTick_Handler`** mit einer eigenen
  Funktion (`extern "C" void SysTick_Handler(void)`, zählt `system_millis`
  hoch). Alle anderen 51 Handler bleiben schwache Aliase auf
  `Default_Handler`:

  ```text
  (gdb) print &HardFault_Handler   -> 0x800067c <Default_Handler>
  (gdb) print &USART2_IRQHandler   -> 0x800067c <Default_Handler>
  (gdb) print &SysTick_Handler     -> 0x800018c <(anonymous namespace)::SysTick_Handler()>
  $ arm-none-eabi-nm build/debug/stm32f103rb-app | grep -c " W .*Handler$"
  51
  (gdb) x/wx 0x0800003c            -> 0x0800018d   (Vektor 15 = SysTick, +1 = Thumb-Bit)
  ```

  Das `extern "C"` ist entscheidend: Ohne es würde der C++-Compiler den
  Namen „manglen“ (z. B. `_ZN12_GLOBAL__N_115SysTick_HandlerEv`), der Linker
  fände keine starke Definition namens `SysTick_Handler`, und SysTick liefe
  stillschweigend in `Default_Handler`. `extern "C"` sorgt dafür, dass das
  Symbol trotz anonymem Namespace exakt `SysTick_Handler` heißt
  (`nm`: `T SysTick_Handler`). Dass GDB es als
  `(anonymous namespace)::SysTick_Handler()` anzeigt, liegt nur an den
  Debug-Infos.

  Vorsicht beim Nachprüfen mit `info symbol HardFault_Handler`: GDB
  antwortet `WWDG_IRQHandler in section .text`. Kein Fehler, an
  `0x0800_067C` liegen eben über 50 Namen, und `info symbol` nennt
  irgendeinen davon.

---

## Teil 6: Der Stack

Demo: [gdb/teil6.gdb](gdb/teil6.gdb) (6.2 bis 6.4) und
[gdb/teil6_overflow.gdb](gdb/teil6_overflow.gdb) (6.5, braucht den Build mit
`stackDemo(0, 2000)`)

**6.1** `stackDemo()`, `g_stack_probe` und `g_stack_result` sind wie
vorgegeben in [src/main.cpp](../src/main.cpp) eingebaut, Aufruf
`g_stack_result = stackDemo(0, 5);` nach `heap_demo();`.

> **Adressen verschieben sich.** Durch den neuen Code (`stackDemo` liegt bei
> `0x0800_018C`, ganz vorne in `.text`) und die neuen `.bss`-Variablen
> ändern sich viele Adressen aus Teil 1 bis 5. Die Zusammenhänge bleiben
> gleich:
>
> | Symbol | bis Teil 5 | ab Teil 6 |
> | --- | --- | --- |
> | `Reset_Handler` | `0x0800_061C` | `0x0800_0680` |
> | `main` | `0x0800_0570` | `0x0800_05C4` |
> | `kRodataBanner` | `0x0800_0C2C` | `0x0800_0C90` |
> | `_sidata` | `0x0800_0E30` | `0x0800_0E94` |
> | `g_stack_probe` (neu, 24 Byte) | – | `0x2000_0174` |
> | `g_stack_result` (neu) | – | `0x2000_018C` |
> | `g_bss_counter` | `0x2000_0174` | `0x2000_0190` |
> | `current_heap_end` | `0x2000_019C` | `0x2000_01B8` |
> | `_ebss` / `_heap_start` | `0x2000_0470` | `0x2000_048C` / `0x2000_0490` |
>
> `.data` bleibt unverändert (keine neue Variable mit Startwert), `.bss`
> wächst von 792 auf 820 Byte. Weil `_ebss` jetzt nicht mehr auf 8 Byte
> ausgerichtet ist, liegt `_heap_start` (`ALIGN(8)`) 4 Byte dahinter.

**6.2 Vorübung `stack_probe`:**

```text
(gdb) x/i $pc        (Halt auf Zeile 156)
=> 0x8000416 <print_memory_layout()+6>: mov.w   r3, #2779096485 @ 0xa5a5a5a5
(gdb) next
(gdb) print &stack_probe   -> 0x20004fd0
(gdb) print/x $sp          -> 0x20004fd0
(gdb) info frame
Stack level 0, frame at 0x20004fe8:
 ... saved pc = 0x80005fc
 called by frame at 0x20004ff0
 Saved registers:
  r7 at 0x20004fe0, lr at 0x20004fe4
```

`&stack_probe` liegt genau bei `$sp` und nur `0x30` = 48 Byte unter
`_stack_top` (`0x2000_5000`). Der Wert `0xA5A5A5A5` landet **nicht** in
`.data`, weil `stack_probe` eine **lokale** Variable ist. Sie existiert erst,
wenn die Funktion läuft, und zwar bei jedem Aufruf neu an der Stelle, auf die
der SP gerade zeigt. Der Startwert kann deshalb nicht vorab an eine feste
Adresse kopiert werden. Der Compiler erzeugt stattdessen **Befehle**, die den
Wert bei jedem Aufruf hineinschreiben: `mov.w r3, #0xa5a5a5a5` (der Wert
steckt im Befehl selbst, also in `.text`), danach `str r3, [r7, #0]`.

**6.2 Hauptteil:**

```text
(gdb) break stackDemo
(gdb) continue
Breakpoint 4, stackDemo (depth=0, maxDepth=5) at .../main.cpp:25
(gdb) bt
#0  stackDemo (depth=0, maxDepth=5) at .../main.cpp:25
#1  0x08000608 in main () at .../main.cpp:224
(gdb) print $sp      -> (void *) 0x20004fd0
(gdb) print &local   -> (volatile int *) 0x20004fdc
(gdb) display depth
(gdb) display/x $sp
(gdb) continue
1: depth = 1
2: /x $sp = 0x20004fb8
(gdb) continue
1: depth = 2
2: /x $sp = 0x20004fa0
```

Am Ende der Rekursion (`frame 5` = Ebene `depth = 0` auswählen, dann
`finish` läuft genau bis zu deren Rücksprung nach `main`):

```text
(gdb) finish
Run till exit from #5  0x080001c8 in stackDemo (depth=0, maxDepth=5) ...
0x08000608 in main () at .../main.cpp:224
Value returned is $13 = 150
(gdb) x/6wx g_stack_probe
0x20000174 <g_stack_probe>:     0x20004fdc      0x20004fc4      0x20004fac      0x20004f94
0x20000184 <g_stack_probe+16>:  0x20004f7c      0x20004f64
```

(`150` = 0 + 10 + 20 + 30 + 40 + 50. Ein einfaches `finish` in Ebene 5
kehrte nur in Ebene 4 zurück.)

| Ebene (`depth`) | Adresse von `local` | Differenz zur vorherigen Ebene |
| --- | --- | --- |
| 0 | `0x2000_4FDC` | – |
| 1 | `0x2000_4FC4` | −24 (`0x18`) |
| 2 | `0x2000_4FAC` | −24 |
| 3 | `0x2000_4F94` | −24 |
| 4 | `0x2000_4F7C` | −24 |
| 5 | `0x2000_4F64` | −24 |

- **6.1** Die Adressen werden mit jeder Ebene **kleiner**. Jeder neue Aufruf
  legt seinen Frame **unter** den des Aufrufers: Der Stack wächst auf dem
  Cortex-M **nach unten**, von `_stack_top` in Richtung `.bss`.
- **6.2** Ein Frame von `stackDemo` ist **24 Byte** groß: `push {r7, lr}`
  (8 Byte) + `sub sp, #16` (16 Byte). 24 ist durch 8 teilbar, der SP bleibt
  also an jeder Funktionsgrenze 8-Byte-ausgerichtet (AAPCS). Inhaltlich
  bräuchte der Frame nur 20 Byte (2 Argumente, `local`, `r7`, `lr`). Die
  4 Byte Füllung (Padding) kommen genau von dieser Regel.
- **6.3** Sechs Ebenen verbrauchen 6 × 24 = **144 Byte** (SP in `main`
  `0x2000_4FE8`, in Ebene 5 `0x2000_4F58`). In die reservierten
  2 KiB passen 2048 / 24 = **85 Ebenen**. Weil `Reset_Handler` und `main`
  davon schon 24 Byte belegen, sind es eigentlich nur
  (2048 − 24) / 24 = **84**. Echte Programme brauchen außerdem Reserve für
  Interrupts: Jede Exception legt mindestens 32 Byte (8 Register) zusätzlich
  auf den Stack, siehe Bonus 2.

**6.3 Frame zerlegen** (Halt in `depth = 2`, Breakpoint am Anfang von
Zeile 25):

```text
(gdb) disassemble stackDemo
   0x0800018c <+0>:     push    {r7, lr}
   0x0800018e <+2>:     sub     sp, #16
   0x08000190 <+4>:     add     r7, sp, #0
   0x08000192 <+6>:     str     r0, [r7, #4]        <- depth
   0x08000194 <+8>:     str     r1, [r7, #0]        <- maxDepth
=> 0x08000196 <+10>:    ldr     r2, [r7, #4]
   ...
   0x080001a0 <+20>:    str     r3, [r7, #12]       <- local = depth * 10
   ...
   0x080001c4 <+56>:    bl      0x800018c <_Z9stackDemoii>
   0x080001c8 <+60>:    mov     r2, r0              <- hierhin geht der Rücksprung
   ...
   0x080001d4 <+72>:    adds    r7, #16
   0x080001d6 <+74>:    mov     sp, r7              <- Epilog: Platz freigeben
   0x080001d8 <+76>:    pop     {r7, pc}            <- Rücksprung
(gdb) x/8wx $sp
0x20004fa0:     0x00000005      0x00000002      0x20004fb4      0x33323130
0x20004fb0:     0x20004fb8      0x080001c9      0x00000005      0x00000001
(gdb) next
(gdb) x/8wx $sp
0x20004fa0:     0x00000005      0x00000002      0x20004fb4      0x00000014
0x20004fb0:     0x20004fb8      0x080001c9      0x00000005      0x00000001
(gdb) info frame
Stack level 0, frame at 0x20004fb8:
 pc = 0x8000196 in stackDemo (.../main.cpp:25); saved pc = 0x80001c8
 called by frame at 0x20004fd0
 Arglist at 0x20004fa0, args: depth=2, maxDepth=5
 Saved registers:
  r7 at 0x20004fb0, lr at 0x20004fb4
(gdb) info symbol 0x080001c8
stackDemo(int, int) + 60 in section .text
```

Der Frame von Ebene 2, Wort für Wort:

```text
hohe Adressen
0x2000_4FBC  0x00000001  depth    \  Frame von Ebene 1 (Aufrufer)
0x2000_4FB8  0x00000005  maxDepth /  <- "frame at 0x20004fb8" = SP vor dem Aufruf
             ----------------------------------------------------------
0x2000_4FB4  0x080001C9  gesicherter lr  -> stackDemo+60 (Ebene 1), Thumb-Bit gesetzt
0x2000_4FB0  0x20004FB8  gesicherter r7  (Frame Pointer von Ebene 1)
0x2000_4FAC  0x00000014  local = 20      (vor "next" noch Müll: 0x33323130)
0x2000_4FA8  0x20004FB4  Padding (nie beschrieben, alter Inhalt)
0x2000_4FA4  0x00000002  depth
0x2000_4FA0  0x00000005  maxDepth        <- SP = r7
niedrige Adressen
```

1. `sp` = `0x2000_4FA0`, `&local` = `0x2000_4FAC` = `sp + 12`. `local`
   liegt also im oberen Teil des Frames, direkt unter den gesicherten
   Registern. Die Argumente aus `r0`/`r1` hat der Debug-Build ganz unten
   abgelegt.
2. Der gespeicherte `lr` ist `0x0800_01C9` (bei `sp + 20`). Ohne Thumb-Bit
   ergibt das `0x0800_01C8` = `stackDemo + 60`: der Befehl direkt **nach**
   dem `bl` in der aufrufenden Ebene 1.
3. `info frame` bestätigt das: `saved pc = 0x80001c8`, `lr at 0x20004fb4`,
   `r7 at 0x20004fb0`, `called by frame at 0x20004fd0` (Frame von Ebene 1).
   `bt` zeigt dieselbe Adresse als `#1 0x080001c8 in stackDemo (depth=1, ...)`.
   GDB baut den Backtrace genau aus diesen gesicherten `lr`-Werten auf.
4. **Überschriebene Rücksprungadresse:** `pop {r7, pc}` lädt blind, was an
   `sp + 20` steht, in den PC. Schreibt z. B. ein lokaler Puffer über sein
   Ende hinaus (Pufferüberlauf), springt die Funktion beim Rücksprung an
   eine **beliebige Adresse**. Das führt im harmlosen Fall zu einem HardFault,
   im schlimmsten Fall wird gezielt fremder Code ausgeführt: Das ist der
   klassische **Stack-Smashing-Angriff**. Auch ein überschriebener `r7`
   zerstört den Frame des Aufrufers.

Nebenbei sieht man, dass ein Stack-Frame **nicht initialisiert** wird. Vor
dem `next` steht in `local` noch `0x33323130`, das sind die ASCII-Zeichen
`'0' '1' '2' '3'` eines früheren Aufrufs (vermutlich der Ziffernpuffer von
`uart_write_dec`). Das Padding-Wort enthält ebenfalls einen Rest. Deshalb
haben nicht initialisierte lokale Variablen in C/C++ einen zufälligen Wert.

**6.4 Stack-Verbrauch bis `main`:**

```text
(gdb) tbreak main
(gdb) continue
(gdb) print/x $sp          -> 0x20004fe8
(gdb) print/x &_stack_top
Missing ELF symbol "(anonymous namespace)::_stack_top".
```

Das ist derselbe Stolperstein wie in Teil 5: In `main.cpp` sucht GDB
`_stack_top` im anonymen Namespace. Abhilfe: die Adresse vorher in C-Code
merken (`set $stack_top = (char*)&_stack_top` im `Reset_Handler`), oder
direkt `0x20005000` verwenden.

**Frage 6.4:** `0x2000_5000 − 0x2000_4FE8` = **24 Byte**.

```text
(gdb) bt
#0  main () at .../main.cpp:212
(gdb) set backtrace past-main on
(gdb) bt
#0  main () at .../main.cpp:212
#1  0x080006c8 in Reset_Handler () at .../startup_stm32f103rb.c:155
```

Standardmäßig hört `bt` bei `main` auf. Mit `set backtrace past-main on`
zeigt GDB auch den Aufrufer `Reset_Handler`. Die 24 Byte setzen sich so
zusammen:

| Wer | Prolog | Byte |
| --- | --- | --- |
| `Reset_Handler` | `push {r7, lr}` + `sub sp, #8` (lokale `src`, `dst`) | 16 |
| `main` | `push {r7, lr}` (keine lokalen Variablen) | 8 |

Die Hardware selbst legt beim Reset nichts auf den Stack. Sie lädt nur den
SP aus der Vektortabelle (`0x2000_5000`).

**6.5 Experiment Stack Overflow** (`stackDemo(0, 2000)`):

```text
(gdb) watch g_data_counter
(gdb) continue
Old value = 305419896
New value = 305419897
main () at .../main.cpp:214            <- Halt 1: main selbst, das ist korrekt
(gdb) continue
Old value = 305419897
New value = 536870920                  <- 0x20000008
0x0800018e in stackDemo (depth=0, maxDepth=0) at .../main.cpp:23
(gdb) x/i $pc-2
   0x800018c <_Z9stackDemoii>:  push    {r7, lr}
(gdb) print/x $sp          -> 0x20000000
(gdb) info registers r7 lr
r7             0x20000008
lr             0x80001c9
(gdb) bt 3
#0  0x0800018e in stackDemo (depth=0, maxDepth=0) at .../main.cpp:23
#1  0x080001c8 in stackDemo (depth=851, maxDepth=2000) at .../main.cpp:32
#2  0x080001c8 in stackDemo (depth=850, maxDepth=2000) at .../main.cpp:32
(gdb) x/2wx 0x20000000
0x20000000 <g_data_counter>:    0x20000008      0x080001c9
(gdb) continue
main () at .../main.cpp:235            <- Halt 3: kein Absturz!
(gdb) print/x g_data_counter          -> 0x20000009
(gdb) print/x _sbrk::current_heap_end -> 0x7d0
```

Achtung: Der Watchpoint hält **zuerst in `main`** (die Zeile
`g_data_counter = g_data_counter + 1U;`). Das ist erlaubt. Erst das zweite
`continue` zeigt den Übeltäter.

- **6.5** Den Wert hat **kein Quelltext**, sondern der Befehl
  `push {r7, lr}` im Prolog von `stackDemo` geändert, in Ebene 852
  (`bt` zeigt die Aufrufer 851, 850, …; Ebene 852 selbst hat ihre Argumente
  noch nicht gespeichert, deshalb die Müllwerte `depth=0, maxDepth=0`).
  Rechnung: Ebene *n* hat SP = `0x2000_4FD0 − 24·n`. Bei *n* = 852 legt
  `push` den alten Frame Pointer (`r7` = `0x2000_0008`) genau auf
  `0x2000_0000` = `g_data_counter` und die Rücksprungadresse
  (`0x0800_01C9`) auf `0x2000_0004` = `rcc_ahb_frequency` (libopencm3).

  Auf dem Weg nach unten ist der Stack der Reihe nach durch **alle**
  Bereiche gewachsen: freier Platz → Heap (der 64-Byte-Block von
  `heap_demo` bei `0x2000_0490`) → `.bss` (u. a. `current_heap_end`,
  `g_stack_probe`, `g_bss_counter`) → `.data` → **unter das RAM**
  (`0x1FFF_xxxx`). Die Folgeschäden sind sichtbar, das Programm läuft aber
  ganz normal weiter:
  - Renode gibt `tick data=0x20000008`, `0x20000009`, … aus statt
    `0x12345679`, …
  - `current_heap_end` = `0x7D0` (2000, der Wert von `maxDepth` aus einem
    Frame). Der nächste `malloc` bekäme „Heap“ an Adresse `0x7D0`.
  - `g_stack_probe` = `{0x344, 0x20004fc4, 0x20a8, 0x20000188, 0x80001c9, 0x7d0}`
    statt der Adressen aus 6.2.
  - `g_stack_result` = 36 529 720 statt 19 990 000.

  > **Warum kein Absturz?** Renode bildet den Adressbereich
  > `0x0000_0000`–`0x1FFF_FFFF` als **beschreibbaren** Speicher ab
  > (`/opt/renode/platforms/cpus/stm32f103.repl`:
  > `flash: Memory.MappedMemory @ sysbus 0x00000000, size: 0x20000000`).
  > Die Frames unterhalb von `0x2000_0000` landen dort und bleiben intakt,
  > deshalb funktionieren sogar alle Rücksprünge. Auf dem echten STM32F103RB
  > liegt unter `0x2000_0000` kein RAM (`0x1FFF_F000` ist der
  > ROM-Bootloader, darunter ist der Bereich reserviert). Spätestens dort
  > gäbe es einen BusFault bzw. HardFault, und die CPU bliebe in
  > `Default_Handler` hängen. Die Zerstörung von Heap, `.bss` und `.data`
  > passiert aber **in beiden Fällen völlig lautlos** und viel früher.
- **6.6** Kein „Segmentation fault“, weil niemand prüft:
  - Es gibt **kein Betriebssystem** und **keine MMU**, die jedem Prozess
    seinen Speicher zuteilt und Zugriffe außerhalb abfängt.
  - Der STM32F103RB hat auch **keine MPU** (Memory Protection Unit). Ohne
    sie darf jeder Befehl jede RAM-Adresse beschreiben.
  - `_stack_limit` und `_Min_Stack_Size` sind nur **Zahlen im
    Linker-Script**. Der Linker prüft damit beim Bauen, ob `.data` + `.bss`
    + 2 KiB ins RAM passen. Zur Laufzeit vergleicht die Hardware den SP mit
    nichts. Der Cortex-M3 hat (anders als Cortex-M33) kein
    Stack-Limit-Register.
  - Aus Sicht der CPU ist ein `push` auf `.data` ein ganz normaler,
    gültiger Speicherzugriff.
- **6.7** Möglichkeiten, Stack Overflows zu vermeiden oder früh zu erkennen:
  1. **Rekursion und große lokale Arrays vermeiden**, Rekursionstiefe
     begrenzen oder iterativ programmieren. Große Puffer `static` oder
     global anlegen, dann sieht man sie in `size`.
  2. **Stack-Bedarf messen bzw. berechnen:** `-fstack-usage` erzeugt pro
     Funktion eine `.su`-Datei mit der Frame-Größe (hier wären es 24 Byte),
     `-Wstack-usage=<n>` warnt bei zu großen Frames. Daraus und aus dem
     Aufrufgraphen ergibt sich der Worst Case, dann `_Min_Stack_Size`
     passend wählen.
  3. **Stack-Painting** (Bonus 5): Stack beim Start mit einem Muster
     (z. B. `0xA5A5A5A5`) füllen und später nachsehen, bis wohin es
     überschrieben wurde (High-Water-Mark).
  4. **Wächter am Stack-Ende:** ein bekanntes Wort („Canary“) bei
     `_stack_limit` regelmäßig prüfen, oder im Debugger
     `watch *(uint32_t*)0x20004800` setzen (Hardware-Watchpoint auf
     `_stack_limit`).
  5. **Hardware-Schutz** auf größeren Chips: MPU-Schutzbereich (Guard
     Region) unter dem Stack, oder auf Cortex-M33 das Register `MSPLIM`.
     Ein Overflow löst dann sofort einen Fault aus.
  6. **Stack nach unten ins RAM legen** (unter `.data`/`.bss`): Ein
     Overflow läuft dann sofort aus dem RAM heraus und erzeugt auf echter
     Hardware einen BusFault, statt Variablen zu zerstören.

Danach ist der Aufruf in `main()` wieder auf `stackDemo(0, 5)` gestellt.
