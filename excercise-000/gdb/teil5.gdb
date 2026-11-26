# Teil 5: Der Startup-Code – was passiert vor main?
#
# Voraussetzung (Terminal 1, Projekt-Hauptverzeichnis):
#   renode --disable-xwt --console renode/nucleo.resc
# Start (Terminal 2, Projekt-Hauptverzeichnis):
#   gdb-multiarch -x excercise-000/gdb/teil5.gdb build/debug/stm32f103rb-app

set pagination off
set confirm off
set language c++
target remote localhost:3333

# Zuerst auf die allererste Instruktion von Reset_Handler zuruecksetzen.
# Grund: Steht die CPU in main.cpp, sucht GDB _sdata & Co. im anonymen
# Namespace von main.cpp (dort per extern "C" deklariert) und scheitert:
#   Missing ELF symbol "(anonymous namespace)::_sdata"
# Im Reset_Handler (C-Code) werden die Linker-Symbole direkt gefunden.
tbreak *Reset_Handler
monitor sysbus.cpu Reset
maintenance flush register-cache
continue

echo \n=== 5.2 Linker-Symbole (nm) ===\n
shell arm-none-eabi-nm -n build/debug/stm32f103rb-app | grep -E " (_sidata|_sdata|_edata|_sbss|_ebss|_estack|_stack_top|_stack_limit|_heap_start|_heap_end|_end|_Min_Stack_Size)$"

echo \n=== 5.2 Dieselben Symbole in GDB: immer mit & (Adresse, kein Inhalt) ===\n
print/x &_sidata
print/x &_sdata
print/x &_edata
print/x &_sbss
print/x &_ebss
echo Groesse .data in Byte:\n
print (char*)&_edata - (char*)&_sdata
echo Groesse .bss in Byte:\n
print (char*)&_ebss - (char*)&_sbss
shell arm-none-eabi-size --format=sysv build/debug/stm32f103rb-app | grep -E "^\.(data|bss) "

echo \n=== 5.2 Wer belegt .data? (nm -S) ===\n
shell arm-none-eabi-nm -n -S -C build/debug/stm32f103rb-app | awk '$1>="20000000" && $1<"20000158" && NF>=4'

echo \n=== 5.3 Reset_Handler: Maschinencode mit Quelltext ===\n
disassemble /s Reset_Handler
echo Literal-Pool am Ende (keine Befehle, sondern die Adressen der Linker-Symbole):\n
x/5wx (char*)Reset_Handler + 76

echo \n=== 5.4 Wir stehen noch auf der allerersten Instruktion von Reset_Handler ===\n
set $pdata = &'(anonymous namespace)::g_data_counter'
set $pbss  = &'(anonymous namespace)::g_bss_counter'
print $pdata
print $pbss
info registers sp pc
info symbol $pc

echo \n=== Vorher-Zustand (RAM nach Reset NICHT geloescht) ===\n
x/wx $pdata
x/wx $pbss
echo RAM vergiften: g_bss_counter = 0xDEADBEEF\n
set var *$pbss = 0xDEADBEEF
x/wx $pbss
echo Startwert von g_data_counter im Flash (_sidata + 0):\n
x/wx &_sidata

echo \n=== Watchpoint: wer schreibt in g_data_counter? ===\n
# Erst vergiften, damit der Kopiervorgang den Wert sichtbar aendert
set var *$pdata = 0
watch *$pdata
continue
info symbol $pc
x/i $pc
bt
print/x *$pdata
delete

echo \n=== Watchpoint: wer nullt g_bss_counter? ===\n
watch *$pbss
continue
info symbol $pc
x/i $pc
print/x *$pbss
delete

echo \n=== Bis main: Ergebnis des Startup-Codes ===\n
tbreak main
continue
print/x *$pdata
print/x *$pbss

echo \n=== 5.3 __libc_init_array: Eintraege in .init_array ===\n
x/2a &__init_array_start

echo \n=== 5.5 Welche Handler ueberschreibt main.cpp? ===\n
# Weak-Aliase teilen sich EINE Adresse mit Default_Handler.
# info symbol nennt dann irgendeinen der Namen (z. B. WWDG_IRQHandler).
print &Default_Handler
print &HardFault_Handler
print &USART2_IRQHandler
print &SysTick_Handler
shell arm-none-eabi-nm -n build/debug/stm32f103rb-app | grep -c " W .*Handler$"
shell arm-none-eabi-nm -n build/debug/stm32f103rb-app | grep -E " T .*Handler$"
echo Vektortabelle: Wort 0 (SP), Wort 1 (Reset), Wort 15 (SysTick):\n
x/2wx 0x08000000
x/wx 0x0800003c
