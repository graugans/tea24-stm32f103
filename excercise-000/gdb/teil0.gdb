# Teil 0: Aufwärmen – Schritt für Schritt durch main
#
# Voraussetzung (Terminal 1, Projekt-Hauptverzeichnis):
#   renode --disable-xwt --console renode/nucleo.resc
# Start (Terminal 2, Projekt-Hauptverzeichnis):
#   gdb-multiarch -x excercise-000/gdb/teil0.gdb build/debug/stm32f103rb-app

set pagination off
set confirm off
target remote localhost:3333

# Immer vom gleichen Startpunkt aus beginnen (auch bei bereits laufender Sitzung)
monitor sysbus.cpu Reset
tbreak main
continue

echo \n=== 0.2: next bis zum ersten LED-Wechsel (LED-Zustand nach jedem Schritt) ===\n
set $n = 1
while $n <= 11
  printf "\n--- next %d ---\n", $n
  next
  monitor sysbus.gpioPortA.led State
  set $n = $n + 1
end

echo \n=== Ergebnis: Nach dem 11. next ist gpio_toggle ausgeführt, die LED ist an. ===\n
echo \n=== 0.3/0.4 jetzt interaktiv: ===\n
echo   (gdb) continue      -> in Terminal 1 laufen tick-Zeilen\n
echo   Ctrl+C              -> anhalten\n
echo   (gdb) bt            -> meist in delay_ms\n
echo   (gdb) info symbol $pc\n
echo   (gdb) finish        -> aus delay_ms zurück nach main\n
echo ACHTUNG: In delay_ms KEIN next/step! Die Warteschleife ist eine einzige\n
echo Zeile, GDB müsste ~24 Mio. Instruktionen einzeln steppen (scheinbares Hängen).\n
echo Falls doch passiert: Ctrl+C.\n\n
