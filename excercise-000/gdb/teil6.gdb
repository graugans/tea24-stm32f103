# Teil 6: Der Stack (6.2 bis 6.4)
#
# Voraussetzung: stackDemo() aus Teil 6.1 ist in src/main.cpp eingebaut,
# Aufruf in main(): g_stack_result = stackDemo(0, 5);
#   cmake --build --preset debug
# Renode danach NEU starten (Terminal 1, Projekt-Hauptverzeichnis):
#   renode --disable-xwt --console renode/nucleo.resc
# Start (Terminal 2, Projekt-Hauptverzeichnis):
#   gdb-multiarch -x excercise-000/gdb/teil6.gdb build/debug/stm32f103rb-app

set pagination off
set confirm off
set language c++
target remote localhost:3333

tbreak *Reset_Handler
monitor sysbus.cpu Reset
maintenance flush register-cache
continue

echo \n=== 6.4 Stack-Verbrauch bis main ===\n
print/x $sp
# In main() scheitert "print &_stack_top" (Missing ELF symbol
# "(anonymous namespace)::_stack_top", siehe Teil 5). Deshalb die Adresse
# hier im C-Code des Reset_Handler in einer GDB-Variable merken:
set $stack_top = (char*)&_stack_top
print (void*)$stack_top
tbreak main
continue
print/x $sp
print $stack_top - (char*)$sp
echo bt hoert standardmaessig bei main auf:\n
bt
set backtrace past-main on
bt
info frame
disassemble /s main,+4
disassemble /s Reset_Handler,+6

echo \n=== 6.2 Vorübung: stack_probe in print_memory_layout ===\n
tbreak print_memory_layout
continue
echo Der Startwert 0xA5A5A5A5 steckt im Befehl (mov.w), nicht in .data:\n
x/i $pc
next
print &stack_probe
print/x stack_probe
print/x $sp
info frame

echo \n=== 6.2 Hauptteil: Rekursion stackDemo ===\n
break stackDemo
continue
bt
info frame
print $sp
print &local
print depth
display depth
display/x $sp
continue
continue
echo \n=== 6.3 Frame zerlegen (depth = 2) ===\n
bt
disassemble stackDemo
x/8wx $sp
echo Gesicherter lr steht bei $sp + 20, ohne Thumb-Bit:\n
print/x *(unsigned*)($sp + 20)
info symbol *(unsigned*)($sp + 20) - 1
echo Nach "next" ist local gesetzt (vorher stand dort noch alter Stack-Inhalt):\n
next
x/8wx $sp
print &local

echo \n=== 6.2 Rekursion bis zum Ende ===\n
undisplay
delete
break stackDemo if depth == 5
continue
bt
print/x $sp
delete
echo Frame von depth 0 auswaehlen und bis zu dessen Ruecksprung laufen:\n
frame 5
finish
next
print g_stack_result
x/6wx g_stack_probe
print/x g_stack_probe
printf "depth  &local       Differenz\n"
set $i = 0
while $i < 6
  if $i == 0
    printf "  %d    0x%08x   -\n", $i, g_stack_probe[$i]
  else
    printf "  %d    0x%08x   %d\n", $i, g_stack_probe[$i], (int)(g_stack_probe[$i] - g_stack_probe[$i-1])
  end
  set $i = $i + 1
end
