# Teil 8: Das Gesamtbild – alle Werte für die Speicherkarte
#
# Voraussetzung (Terminal 1, Projekt-Hauptverzeichnis):
#   renode --disable-xwt --console renode/nucleo.resc
# Start (Terminal 2, Projekt-Hauptverzeichnis):
#   gdb-multiarch -x excercise-000/gdb/teil8.gdb build/debug/stm32f103rb-app

set pagination off
set confirm off
target remote localhost:3333

tbreak *Reset_Handler
monitor sysbus.cpu Reset
maintenance flush register-cache
continue

echo \n=== Flash: Abschnitte mit VMA (Laufzeit) und LMA (Ladeadresse) ===\n
shell arm-none-eabi-objdump -h build/debug/stm32f103rb-app | grep -E "Idx|\.isr_vector|\.text|\.data|\.bss|\.noinit"
echo \nWo liegt .rodata? (Map-Datei; bis Bonus 6 innerhalb von .text, danach eigener Abschnitt)\n
shell grep -A12 -E "^ \*\(\.rodata\*\)" build/debug/stm32f103rb-app.map | grep -E "^ \.rodata|^ +0x0800" | head -6

echo \n=== RAM: Linker-Symbole (im C-Code des Reset_Handler auslesen) ===\n
printf "_stack_top   = %p\n", &_stack_top
printf "_stack_limit = %p   (= _heap_end)\n", &_stack_limit
printf "_heap_start  = %p   (= _end)\n", &_heap_start
printf "_ebss        = %p\n", &_ebss
printf "_sbss        = %p   (= _edata)\n", &_sbss
printf "_sdata       = %p\n", &_sdata
printf "_sidata      = %p   (Startwerte von .data im Flash)\n", &_sidata
printf ".data: %d Byte, .bss: %d Byte, Heap-Kapazitaet: %d Byte\n", (char*)&_edata - (char*)&_sdata, (char*)&_ebss - (char*)&_sbss, (char*)&_heap_end - (char*)&_heap_start
set $stack_top = (char*)&_stack_top
set $heap_start = (char*)&_heap_start

echo \n=== Gemessener Zustand: tiefste Stelle von stackDemo und Heap-Belegung ===\n
break stackDemo if depth == 5
continue
printf "SP in stackDemo(depth=5) = %p  -> %d Byte Stack belegt\n", $sp, $stack_top - (char*)$sp
delete
printf "current_heap_end         = %p  -> %d Byte Heap belegt\n", _sbrk::current_heap_end, (char*)_sbrk::current_heap_end - $heap_start
printf "g_heap_ptr (malloc 32)   = %p\n", g_heap_ptr
printf "Abstand Heap-Ende bis SP = %d Byte frei\n", (char*)$sp - (char*)_sbrk::current_heap_end
