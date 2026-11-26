# Bonus 2, Zusatz: HardFault durch __builtin_trap()
#
# Voraussetzung: In main() steht vorübergehend direkt nach dem stackDemo-Aufruf
#   __builtin_trap();
#   cmake --build --preset debug
# Renode NEU starten (Terminal 1, Projekt-Hauptverzeichnis):
#   renode --disable-xwt --console renode/nucleo.resc
# Start (Terminal 2, Projekt-Hauptverzeichnis):
#   gdb-multiarch -x excercise-000/gdb/bonus2_hardfault.gdb build/debug/stm32f103rb-app
# Danach __builtin_trap() wieder entfernen!

set pagination off
set confirm off
set language c++
target remote localhost:3333

tbreak *Reset_Handler
monitor sysbus.cpu Reset
maintenance flush register-cache
continue

echo \n=== __builtin_trap() im Maschinencode ===\n
shell arm-none-eabi-objdump -d build/debug/stm32f103rb-app | grep -m1 "udf"

echo \n=== Breakpoint auf HardFault_Handler (= Default_Handler) ===\n
break *HardFault_Handler
continue
info symbol $pc
bt
info registers lr sp xpsr
echo Exception-Nummer (xpsr & 0x1ff), 3 = HardFault:\n
print $xpsr & 0x1ff
echo Exception-Frame: r0 r1 r2 r3 / r12 lr pc xpsr\n
x/8wx $sp
set $frame = (unsigned*)$sp
printf "gesicherter pc = 0x%08x  (die fehlerhafte Instruktion)\n", $frame[6]
info symbol $frame[6]
x/i $frame[6]
echo \nFault-Statusregister (SCB):\n
printf "CFSR = 0x%08x  (UFSR = Bits 31..16, Bit 16 UNDEFINSTR)\n", *(unsigned*)0xE000ED28
printf "HFSR = 0x%08x  (Bit 30 FORCED: eskalierter Fault)\n", *(unsigned*)0xE000ED2C
delete

echo \n=== Danach: Endlosschleife in Default_Handler ===\n
stepi
stepi
stepi
info symbol $pc
x/2i Default_Handler
