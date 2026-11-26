# Teil 7: Der Heap und _sbrk
#
# Voraussetzung: malloc-Erweiterung aus Teil 7.3 ist in src/main.cpp eingebaut
# (g_heap_ptr = std::malloc(32); nach heap_demo();)
#   cmake --build --preset debug
# Renode danach NEU starten (Terminal 1, Projekt-Hauptverzeichnis):
#   renode --disable-xwt --console renode/nucleo.resc
# Start (Terminal 2, Projekt-Hauptverzeichnis):
#   gdb-multiarch -x excercise-000/gdb/teil7.gdb build/debug/stm32f103rb-app

set pagination off
set confirm off
target remote localhost:3333

tbreak *Reset_Handler
monitor sysbus.cpu Reset
maintenance flush register-cache
continue

# Linker-Symbole hier (C-Code) in GDB-Variablen merken. Nach "finish" steht
# die CPU in main.cpp, dort scheitert "print &_heap_start" (siehe Teil 5).
set $heap_start = (char*)&_heap_start
set $heap_end   = (char*)&_heap_end

echo \n=== 7.1 Vorab: wo liegt current_heap_end? ===\n
shell arm-none-eabi-nm -n -C build/debug/stm32f103rb-app | grep -E "current_heap_end|_heap_start|_heap_end"
print &_sbrk::current_heap_end
info symbol &_sbrk::current_heap_end

echo \n=== 7.2 Erster Aufruf: heap_demo -> _sbrk(64) ===\n
break _sbrk
continue
bt
print increment
info registers r0
info locals
next
next
next
next
info locals
next
next
info locals
finish
echo Vergleich mit _heap_start / _heap_end:\n
print (void*)$heap_start
print (void*)$heap_end
print/x _sbrk::current_heap_end
print (char*)_sbrk::current_heap_end - $heap_start
echo Heap-Kapazitaet (_heap_end - _heap_start) in Byte:\n
print $heap_end - $heap_start

echo \n=== 7.3 malloc(32): wer ruft _sbrk jetzt auf, und mit wie viel? ===\n
continue
bt
print increment
finish
continue
print increment
finish
print/x _sbrk::current_heap_end
delete
tbreak stackDemo
continue
print g_heap_ptr
echo Chunk-Header von malloc direkt vor dem Block (prev_size, size|1):\n
x/2wx (char*)g_heap_ptr - 8
info symbol &g_heap_ptr
echo Insgesamt von malloc beim Heap angefordert (Byte):\n
print (char*)_sbrk::current_heap_end - $heap_start - 64

echo \n=== Experiment: Heap-Erschoepfung (_sbrk(0x10000) statt 64) ===\n
tbreak *Reset_Handler
monitor sysbus.cpu Reset
maintenance flush register-cache
continue
break _sbrk
continue
bt 2
set var increment = 0x10000
print increment
finish
print/x _sbrk::current_heap_end
print _impure_data._errno
echo (ENOMEM = 12)\n
echo Und malloc danach? Funktioniert trotzdem, der Heap ist ja noch leer:\n
continue
bt 4
finish
delete
tbreak stackDemo
continue
print g_heap_ptr
echo \nRenode (Terminal 1) zeigt nach diesem Lauf: "heap alloc failed"\n
