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

**1.2 Segmentgrößen und Symbole**

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

**1.3 Die Vektortabelle**

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
