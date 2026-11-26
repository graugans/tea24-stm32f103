# Bonus 4: GDB-Skript statt Handarbeit – Stack-Messung automatisiert
#
# Voraussetzung (Terminal 1, Projekt-Hauptverzeichnis):
#   renode --disable-xwt --console renode/nucleo.resc
# Start (Terminal 2, Projekt-Hauptverzeichnis):
#   gdb-multiarch -batch -x excercise-000/gdb/stack.gdb build/debug/stm32f103rb-app
#
# Gegenüber der Vorlage aus der README zwei Ergänzungen:
#  - Reset zu Beginn, damit das Skript beliebig oft laufen kann
#    (stackDemo läuft nur einmal, direkt nach dem Start).
#  - Ein Endpunkt (tbreak gpio_toggle): Sonst läuft das letzte "continue"
#    für immer weiter, und gdb -batch kehrt nie zurück.

set pagination off
target remote localhost:3333

tbreak *Reset_Handler
monitor sysbus.cpu Reset
maintenance flush register-cache
continue

break stackDemo
commands
  silent
  printf "depth=%d sp=0x%08x\n", depth, (unsigned)$sp
  continue
end

tbreak gpio_toggle
commands
  printf "fertig: g_stack_result = %d\n", g_stack_result
end

continue
