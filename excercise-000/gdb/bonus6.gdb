# Bonus 6: .rodata in einem eigenen Abschnitt
#
# Voraussetzung: ld/stm32f103rb.ld mit eigenem .rodata-Block (Bonus 6)
#   cmake --build --preset debug
# Renode NEU starten (Terminal 1, Projekt-Hauptverzeichnis):
#   renode --disable-xwt --console renode/nucleo.resc
# Start (Terminal 2, Projekt-Hauptverzeichnis):
#   gdb-multiarch -x excercise-000/gdb/bonus6.gdb build/debug/stm32f103rb-app

set pagination off
set confirm off
set language c++
target remote localhost:3333

tbreak *Reset_Handler
monitor sysbus.cpu Reset
maintenance flush register-cache
continue

echo \n=== Abschnitte: jetzt mit eigenem .rodata ===\n
shell arm-none-eabi-size --format=sysv build/debug/stm32f103rb-app | grep -E "^(section|\.isr|\.text|\.rodata|\.data|\.bss|\.noinit|Total)"
echo \nVMA und LMA:\n
shell arm-none-eabi-objdump -h build/debug/stm32f103rb-app | grep -E "Idx|\.isr|\.text|\.rodata|\.data|\.bss|\.noinit"
shell ls -l build/debug/stm32f103rb-app.bin

echo \n=== kRodataBanner: nm zeigt jetzt r statt t ===\n
shell arm-none-eabi-nm -C build/debug/stm32f103rb-app | grep kRodataBanner
shell arm-none-eabi-nm build/debug/stm32f103rb-app | awk '/kRodataBanner/ {print "set $banner = 0x" $1}' > build/debug/bonus6-banner.gdb
source build/debug/bonus6-banner.gdb
info symbol $banner
x/s $banner
echo info files (Ausschnitt):\n
info files

echo \n=== Laeuft das Programm unveraendert? ===\n
tbreak gpio_toggle
continue
print g_stack_result
echo Renode-Terminal: Banner und "kRodataBanner (.rodata): 0x08001568"\n
