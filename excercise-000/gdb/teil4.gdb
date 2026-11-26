# Teil 4: Wo liegt was? Die Speichersegmente im Debugger nachweisen
#
# Voraussetzung (Terminal 1, Projekt-Hauptverzeichnis):
#   renode --disable-xwt --console renode/nucleo.resc
# Start (Terminal 2, Projekt-Hauptverzeichnis):
#   gdb-multiarch -x excercise-000/gdb/teil4.gdb build/debug/stm32f103rb-app

set pagination off
set confirm off
set language c++
target remote localhost:3333

monitor sysbus.cpu Reset
maintenance flush register-cache
tbreak main
continue

echo \n=== 4.1 info symbol: Adresse -> Symbol + Abschnitt ===\n
info symbol &g_data_counter
info symbol &g_bss_counter
info symbol &g_bss_buffer
info address main

echo \n=== kRodataBanner ===\n
# Auf diesem Stand kennt GDB fuer kRodataBanner nur den WERT (DWARF), keine Adresse:
#   info symbol kRodataBanner  -> "requires the program to have a function malloc"
# Die ELF-Symboltabelle (nm) kennt die Adresse aber:
shell arm-none-eabi-nm -C build/debug/stm32f103rb-app | grep kRodataBanner
# Adresse aus nm in die GDB-Variable $banner uebernehmen (haengt vom Build ab,
# z. B. 0x08000c2c ohne bzw. 0x08000c90 mit stackDemo aus Teil 6):
shell arm-none-eabi-nm build/debug/stm32f103rb-app | awk '/kRodataBanner/ {print "set $banner = 0x" $1}' > build/debug/teil4-banner.gdb
source build/debug/teil4-banner.gdb
info symbol $banner
x/s $banner

echo \n=== stack_probe (lokal in print_memory_layout) ===\n
tbreak print_memory_layout
continue
print &stack_probe
print $sp
info symbol &stack_probe

echo \n=== current_heap_end (static in _sbrk) ===\n
tbreak _sbrk
continue
print &current_heap_end
info symbol &current_heap_end
print current_heap_end

echo \n=== 4.1 Grenzen von .data und .bss (Linker-Symbole) ===\n
print &_sdata
print &_edata
print &_sbss
print &_ebss

echo \n=== info files: alle Abschnitte mit Adressbereich ===\n
info files

echo \n=== 4.3 Objektdatei main.cpp.o: .rodata gibt es dort noch ===\n
shell arm-none-eabi-size --format=sysv $(find build/debug -name "main.cpp.o*" | head -1) | grep -E "rodata|\.data|\.bss|\.text\.main|section"
