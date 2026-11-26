# Teil 2.1: PC und SP nach dem Start, Vergleich mit der Vektortabelle
#
# Voraussetzung (Terminal 1): Renode frisch gestartet
#   renode --disable-xwt --console excercise-000/gdb/teil2.resc
# Start (Terminal 2, Projekt-Hauptverzeichnis):
#   gdb-multiarch -x excercise-000/gdb/teil2.gdb build/debug/stm32f103rb-app

set pagination off
set confirm off
target remote localhost:3333

echo \n=== Renode-Log in Terminal 1: "Setting initial values: PC = 0x800061D, SP = 0x20005000" (PC ab Teil 6: 0x8000681)  ===\n
echo \n=== Vektortabelle: Wort 0 (initialer SP), Wort 1 (Reset-Vektor) ===\n
x/2wx 0x08000000

echo \n=== Register direkt nach dem Start (aus Sicht von Renode und von GDB) ===\n
monitor sysbus.cpu SP
monitor sysbus.cpu PC
info registers sp pc xpsr

echo \n=== Vergleich ===\n
printf "SP = Wort 0:               0x%08x == 0x%08x\n", $sp, *(unsigned int *)0x08000000
printf "PC = Wort 1 ohne Thumb-Bit: 0x%08x == 0x%08x\n", $pc, *(unsigned int *)0x08000004 & ~1
printf "Thumb-Bit (xPSR Bit 24):    %d\n", ($xpsr >> 24) & 1
info symbol $pc
