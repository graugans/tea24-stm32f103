# Bonus 5: Stack-Painting – maximalen Stack-Verbrauch messen
#
# Voraussetzung (Terminal 1, Projekt-Hauptverzeichnis):
#   renode --disable-xwt --console renode/nucleo.resc
# Start (Terminal 2, Projekt-Hauptverzeichnis):
#   gdb-multiarch -x excercise-000/gdb/bonus5.gdb build/debug/stm32f103rb-app
#
# Gemalt wird ganz am Anfang (erste Instruktion von Reset_Handler, SP = _stack_top).
# So zaehlt auch der Stack von Reset_Handler und main mit. Die README malt ab
# $sp in main; das Ergebnis ist dann um die 24 Byte bis main kleiner.

set pagination off
set confirm off
target remote localhost:3333

tbreak *Reset_Handler
monitor sysbus.cpu Reset
maintenance flush register-cache
continue

# Linker-Symbole hier (C-Code) merken, in main.cpp sind sie nicht erreichbar.
set $top   = (unsigned*)&_stack_top
set $limit = (unsigned*)&_heap_end

echo \n=== 1. Stack-Reserve mit 0xAAAAAAAA bemalen ===\n
printf "von %p bis %p (%d Byte)\n", $limit, (unsigned*)$sp - 1, (char*)$sp - (char*)$limit
set var $p = (unsigned*)$sp - 1
while $p >= $limit
  set var *$p = 0xAAAAAAAA
  set var $p = $p - 1
end
x/4wx $limit
x/4wx $top - 4

echo \n=== 2. Programm bis nach stackDemo(0, 5) laufen lassen ===\n
tbreak gpio_toggle
continue

echo \n=== 3. Wasserstand suchen: von unten nach oben bis zum ersten veraenderten Wort ===\n
define watermark
  set var $p = $limit
  while $p < $top && *$p == 0xAAAAAAAA
    set var $p = $p + 1
  end
  printf "tiefstes beschriebenes Wort: %p\n", $p
  printf "maximaler Stack-Verbrauch:   %d Byte\n", (char*)$top - (char*)$p
  printf "unberuehrt (Reserve):        %d Byte\n", (char*)$p - (char*)$limit
end
watermark
echo Grenze zwischen Muster und Stack-Inhalt:\n
x/16wx (char*)$p - 32
info symbol *($p + 5)

echo \n=== 4. Laenger laufen lassen (3 LED-Takte, jeweils mit delay_ms und SysTick) ===\n
break gpio_toggle
continue
continue
continue
delete
watermark
