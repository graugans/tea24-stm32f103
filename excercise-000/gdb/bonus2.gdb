# Bonus 2: Interrupts und der Exception-Stack-Frame
#
# Voraussetzung (Terminal 1, Projekt-Hauptverzeichnis):
#   renode --disable-xwt --console renode/nucleo.resc
# Start (Terminal 2, Projekt-Hauptverzeichnis):
#   gdb-multiarch -x excercise-000/gdb/bonus2.gdb build/debug/stm32f103rb-app

set pagination off
set confirm off
set language c++
target remote localhost:3333

tbreak *Reset_Handler
monitor sysbus.cpu Reset
maintenance flush register-cache
continue
tbreak stackDemo
continue

echo \n=== SysTick-Interrupt abfangen ===\n
# Breakpoint auf die ERSTE Instruktion (*): SP zeigt dann genau auf den
# Exception-Frame. Hinter dem Prolog laege noch der Frame des Handlers davor.
break *SysTick_Handler
continue
bt
info registers lr pc sp xpsr
echo Exception-Nummer (xpsr & 0x1ff), 15 = SysTick:\n
print $xpsr & 0x1ff
echo Exception-Frame: r0 r1 r2 r3 / r12 lr pc xpsr\n
x/8wx $sp
set $frame = (unsigned*)$sp
printf "gesicherter lr = 0x%08x\n", $frame[5]
printf "gesicherter pc = 0x%08x  (hier wurde unterbrochen)\n", $frame[6]
info symbol $frame[6]
printf "gesicherter xpsr = 0x%08x\n", $frame[7]

echo \n=== Wo wird meistens unterbrochen? 10 SysTicks ===\n
set $i = 0
while $i < 10
  continue
  set $frame = (unsigned*)$sp
  info symbol $frame[6]
  set $i = $i + 1
end
delete

echo \n=== Rueckweg: Handler bis zum bx lr ===\n
break *SysTick_Handler
continue
delete
disassemble SysTick_Handler

echo \n=== Wer aendert system_millis? ===\n
watch '(anonymous namespace)::system_millis'
continue
bt 2
continue
bt 2
delete
echo \n=== Wie oft pro Sekunde? SysTick-Register auslesen ===\n
# STK_CSR (0xE000E010): Bit 2 CLKSOURCE (0 = AHB/8), Bit 1 TICKINT, Bit 0 ENABLE
# STK_RVR (0xE000E014): Reload-Wert, Interrupt alle (RVR + 1) Takte
# Die Firmware schreibt CLKSOURCE = 0 (STK_CSR_CLKSOURCE_AHB_DIV8 = 0U << 2),
# Renode liest Bit 2 aber als 1 zurueck und zaehlt fest mit 72 MHz.
printf "STK_CSR = 0x%08x\n", *(unsigned*)0xE000E010
printf "STK_RVR = %u\n", *(unsigned*)0xE000E014
printf "Echte Hardware: 48 MHz / 8 / %u = %u Hz\n", *(unsigned*)0xE000E014 + 1, 48000000 / 8 / (*(unsigned*)0xE000E014 + 1)
printf "Renode (systickFrequency 72 MHz, ohne /8): %u Hz\n", 72000000 / (*(unsigned*)0xE000E014 + 1)
shell grep -m1 systickFrequency /opt/renode/platforms/cpus/stm32f103.repl
echo Kontrolle im Renode-Terminal: zwischen zwei "tick"-Zeilen (500 Ticks) liegen virtuell ca. 41.66 ms\n
