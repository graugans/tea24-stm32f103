# Teil 6.5: Experiment Stack Overflow
#
# Voraussetzung: In main() steht vorübergehend
#   g_stack_result = stackDemo(0, 2000);
#   cmake --build --preset debug
# Renode danach NEU starten (Terminal 1, Projekt-Hauptverzeichnis):
#   renode --disable-xwt --console renode/nucleo.resc
# Start (Terminal 2, Projekt-Hauptverzeichnis):
#   gdb-multiarch -x excercise-000/gdb/teil6_overflow.gdb build/debug/stm32f103rb-app
# Danach in main() wieder auf stackDemo(0, 5) zurückstellen!

set pagination off
set confirm off
set language c++
target remote localhost:3333

tbreak *Reset_Handler
monitor sysbus.cpu Reset
maintenance flush register-cache
continue
tbreak main
continue

echo \n=== Watchpoint auf g_data_counter ===\n
watch g_data_counter
echo \n--- Halt 1: main selbst (Zeile g_data_counter + 1), das ist erlaubt ---\n
continue
info symbol $pc

echo \n--- Halt 2: der Stack hat .data erreicht ---\n
continue
info symbol $pc
x/i $pc-2
print/x $sp
print/x &g_data_counter
info registers r7 lr
bt 3
echo Welche Variablen hat der Stack auf dem Weg nach unten ueberrollt?\n
x/2wx 0x20000000
info symbol 0x20000004
print/x g_bss_counter
print/x _sbrk::current_heap_end
print/x g_stack_probe

echo \n--- Halt 3: Programm laeuft einfach weiter (kein Absturz!) ---\n
continue
info symbol $pc
print/x $sp
print/x g_data_counter
print g_stack_result
echo current_heap_end (static in _sbrk) nach dem Overflow:\n
print/x _sbrk::current_heap_end
delete
echo \nIn Renode (Terminal 1) beachten: "tick data=0x2000000X" statt 0x1234567X\n
