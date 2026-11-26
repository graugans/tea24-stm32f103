# Bonus 3: Debug- gegen Release-Build (Teil 6.2 mit -O3)
#
# Voraussetzung: Renode mit excercise-000/gdb/bonus3_release.resc gestartet
# Start (Terminal 2, Projekt-Hauptverzeichnis):
#   gdb-multiarch -x excercise-000/gdb/bonus3.gdb build/release/stm32f103rb-app

set pagination off
set confirm off
set language c++
target remote localhost:3333

tbreak *Reset_Handler
monitor sysbus.cpu Reset
maintenance flush register-cache
continue

echo \n=== Groessenvergleich ===\n
shell arm-none-eabi-size build/debug/stm32f103rb-app build/release/stm32f103rb-app

echo \n=== Drei Versionen von stackDemo (Klone fuer konstante Argumente) ===\n
shell arm-none-eabi-nm -n -C build/release/stm32f103rb-app | grep stackDemo
disassemble 'stackDemo(int, int)'

echo \n=== Keine Debug-Infos fuer main.cpp: -O3 ohne -g ===\n
shell grep -o '"command": "[^"]*main.cpp' build/release/compile_commands.json | tr ' ' '\n' | grep -E "^-(O|g)"
info line main
echo Variablennamen (depth, local) gibt es nicht. Wir arbeiten mit Registern\n
echo und Speicher: beim Halt im generischen stackDemo ist r0 = depth, r1 = maxDepth.\n

echo \n=== break stackDemo trifft alle drei Stellen ===\n
break stackDemo
info breakpoints
commands
  silent
  printf "sp=0x%08x  r0=%-10d r1=%d  in ", $sp, $r0, $r1
  info symbol $pc
  continue
end
tbreak gpio_toggle
continue
delete

echo \n=== Ergebnis: Adressen von local, Differenz pro Ebene ===\n
printf "g_stack_result = %d\n", *(int*)&g_stack_result
x/6wx (unsigned*)&g_stack_probe
set $probe = (unsigned*)&g_stack_probe
printf "depth  &local       Differenz\n"
set $i = 0
while $i < 6
  if $i == 0
    printf "  %d    0x%08x   -\n", $i, $probe[$i]
  else
    printf "  %d    0x%08x   %d\n", $i, $probe[$i], (int)($probe[$i] - $probe[$i-1])
  end
  set $i = $i + 1
end

echo \n=== next/finish ohne Zeileninformation ===\n
tbreak *'stackDemo(int, int)'
monitor sysbus.cpu Reset
maintenance flush register-cache
continue
bt
next
x/i $pc
bt 3
