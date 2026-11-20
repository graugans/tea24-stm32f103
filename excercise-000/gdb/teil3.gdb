# Teil 3: GDB verbinden und die wichtigsten Befehle kennenlernen
#
# Voraussetzung (Terminal 1, Projekt-Hauptverzeichnis):
#   renode --disable-xwt --console renode/nucleo.resc
# Start (Terminal 2, Projekt-Hauptverzeichnis):
#   gdb-multiarch -x excercise-000/gdb/teil3.gdb build/debug/stm32f103rb-app

# --- 3.1 Verbinden und komfortable Einstellungen ---
set pagination off
set print pretty on
set confirm off
set language c++
target remote localhost:3333

# Gleicher Startpunkt bei jedem Lauf: Halt auf der ersten Instruktion nach dem Reset
monitor sysbus.cpu Reset
# GDB-Registercache verwerfen, sonst versucht GDB, den Breakpoint am alten PC zu überspringen
maintenance flush register-cache
tbreak *Reset_Handler
continue

echo \n=== 3.2 / Frage 3.1: Zustand direkt nach dem Reset ===\n
info registers sp pc xpsr
info symbol $pc
x/2wx 0x08000000
printf "pc | Thumb-Bit = 0x%08x = Wort 1\n", (unsigned int)$pc | 1

echo \n=== 3.3 Breakpoint auf main, Ablaufsteuerung ===\n
break main
info breakpoints
continue
list
next
next
echo \n--- step in clock_setup() hinein ... ---\n
next
step
bt
echo \n--- ... und mit finish wieder heraus ---\n
finish
echo \n--- stepi: genau eine Maschinenanweisung ---\n
x/i $pc
stepi
x/i $pc
echo \n--- stepi ist in gpio_setup gelandet (bl = Funktionsaufruf); finish zurück nach main ---\n
finish

echo \n=== 3.4 Variablen und Speicher ===\n
print g_data_counter
print/x g_data_counter
print &g_data_counter
print g_bss_counter
ptype g_bss_buffer
print/x *g_bss_buffer@4
# Hinweis: x/s kRodataBanner klappt erst mit dem Fix auf main (f8c1356);
# print funktioniert immer, weil GDB den Wert aus den Debug-Infos kennt.
print kRodataBanner
echo \n--- set var schreibt in den Speicher des Targets ---\n
set var g_bss_counter = 5
print g_bss_counter

echo \n=== 3.5 Stack: backtrace und info frame (in uart_setup) ===\n
tbreak uart_setup
continue
backtrace
info frame
up
info frame
down

echo \n=== 3.6 Renode-Befehle aus GDB ===\n
monitor sysbus.cpu PC
printf "GDB: pc = 0x%08x\n", $pc

delete
echo \n=== Fertig. GDB bleibt interaktiv; z. B. continue und in Terminal 1 die UART-Ausgabe ansehen. ===\n
