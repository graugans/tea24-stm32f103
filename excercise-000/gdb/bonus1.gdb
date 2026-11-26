# Bonus 1: Globale Objekte und Konstruktoren
#
# Voraussetzung: g_ctor_ran / struct Probe / g_probe aus Bonus 1 in src/main.cpp
#   cmake --build --preset debug
# Renode NEU starten (Terminal 1, Projekt-Hauptverzeichnis):
#   renode --disable-xwt --console renode/nucleo.resc
# Start (Terminal 2, Projekt-Hauptverzeichnis):
#   gdb-multiarch -x excercise-000/gdb/bonus1.gdb build/debug/stm32f103rb-app

set pagination off
set confirm off
set language c++
target remote localhost:3333

tbreak *Reset_Handler
monitor sysbus.cpu Reset
maintenance flush register-cache
continue

echo \n=== Die Liste der Konstruktoren: .init_array (im Flash) ===\n
shell arm-none-eabi-nm -n -C build/debug/stm32f103rb-app | grep -E "array_(start|end)|_GLOBAL__sub_I|Probe::Probe"
x/3a &__init_array_start
echo Laenge .preinit_array (Byte):\n
print (char*)&__preinit_array_end - (char*)&__preinit_array_start
echo Laenge .init_array (Byte, 4 pro Eintrag):\n
print (char*)&__init_array_end - (char*)&__init_array_start

echo \n=== Vor dem Startup-Code: RAM vergiften ===\n
set var g_ctor_ran = 0x55
print g_ctor_ran

echo \n=== Wer ruft den Konstruktor auf? ===\n
break Probe::Probe
continue
bt
set backtrace past-main on
bt
echo .bss ist zu diesem Zeitpunkt schon genullt:\n
print g_ctor_ran
delete

echo \n=== Bei main ===\n
tbreak main
continue
print g_ctor_ran
print &g_probe
print sizeof(g_probe)
info symbol &g_probe

echo \n=== Statische Initialisierungsfunktion des Compilers ===\n
disassemble _GLOBAL__sub_I_g_heap_ptr
