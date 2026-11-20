#!/usr/bin/env bash
# Teil 1: Bauen und die ELF-Datei untersuchen (kein GDB nötig)
#
# Start (Projekt-Hauptverzeichnis):
#   excercise-000/gdb/teil1.sh
set -euo pipefail

ELF=build/debug/stm32f103rb-app

step() { printf '\n\033[1m=== %s ===\033[0m\n' "$*"; }

step "1.1 Bauen"
cmake --preset debug > /dev/null
cmake --build --preset debug
ls -l build/debug/stm32f103rb-app*

step "1.1 file: ELF 32-bit, ARM -> läuft nicht auf dem x86-PC"
file "$ELF"

step "1.2 Abschnittsgrößen (Adressen dezimal!) - kein .rodata"
arm-none-eabi-size --format=sysv "$ELF" | grep -v debug

step "1.2 VMA/LMA - nur bei .data (mit CONTENTS) unterscheiden sie sich sinnvoll"
arm-none-eabi-objdump -h "$ELF" | sed -n '/Idx/,/noinit/p'

step "1.2 Variablen aus main.cpp (kleine Buchstaben = internal linkage)"
arm-none-eabi-nm -C -S -n "$ELF" | grep -E "g_|kRodata|system_millis"

step "1.2a Wohin sortiert das Linker-Script .rodata?"
grep -n -B12 '\*(.rodata\*)' ld/stm32f103rb.ld | grep -E '^\s*[0-9]+-\s*\.text|rodata'

step "1.3 Vektortabelle: Wort 0 = initialer SP, Wort 1 = Reset_Handler | 1 (Thumb)"
arm-none-eabi-objdump -s -j .isr_vector "$ELF" | sed -n '4,5p'
arm-none-eabi-nm -n "$ELF" | grep -E ' (_estack|Reset_Handler)$'
