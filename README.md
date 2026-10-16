# STM32F103RB C++ Template (CMake + libopencm3)

## Projektziel

Dieses Projekt ist ein **minimaler, sauberer Startpunkt** für Embedded-C++-Entwicklung auf dem **STM32 Nucleo-F103RB** mit:

- **CMake** Buildsystem
- **Debug/Release** Build-Typen
- **libopencm3** als Open-Source-Hardware-Abstraktion
- **OpenOCD** für Flashing
- **VS Code Debugging** über ST-LINK

Der aktuelle Stand implementiert als ersten Schritt:

- LED-Blink auf **LD2 (PA5)**
- UART-Ausgabe über **USART2 (PA2/PA3, ST-LINK Virtual COM Port)**
- Debug-Setup für Breakpoints und Step-Debugging

---

## Struktur

- [CMakeLists.txt](/workspaces/tea24-stm32/CMakeLists.txt): Firmware-Target, Compiler/Linker-Flags, Flash-Target
- [CMakePresets.json](/workspaces/tea24-stm32/CMakePresets.json): `debug`/`release` Configure- und Build-Presets
- [cmake/arm-none-eabi-gcc.cmake](/workspaces/tea24-stm32/cmake/arm-none-eabi-gcc.cmake): ARM-Toolchain
- [cmake/libopencm3.cmake](/workspaces/tea24-stm32/cmake/libopencm3.cmake): Fetch + Build von libopencm3
- [ld/stm32f103rb.ld](/workspaces/tea24-stm32/ld/stm32f103rb.ld): Linker Script für STM32F103RB (128 KB Flash / 20 KB RAM)
- [src/startup_stm32f103rb.c](/workspaces/tea24-stm32/src/startup_stm32f103rb.c): Vector Table + Reset-Startup
- [src/main.cpp](/workspaces/tea24-stm32/src/main.cpp): Blinky + UART Demo
- [.vscode/launch.json](/workspaces/tea24-stm32/.vscode/launch.json): Cortex-Debug Launch-Konfiguration

---

## Voraussetzungen

Im Dev-Container sollten verfügbar sein:

- `cmake` (>= 3.21)
- `ninja`
- `arm-none-eabi-gcc` Toolchain
- `openocd`

Zusätzlich in VS Code:

- CMake Tools
- Cortex-Debug (bereits in [devcontainer.json](/workspaces/tea24-stm32/.devcontainer/devcontainer.json) ergänzt)

---

## Build

### Debug

```bash
cmake --preset debug
cmake --build --preset debug
```

### Release

```bash
cmake --preset release
cmake --build --preset release
```

Build-Artefakte liegen unter:

- [build/debug/](/workspaces/tea24-stm32/build/debug)
- [build/release/](/workspaces/tea24-stm32/build/release)

Nach dem Build werden zusätzlich erzeugt:

- `stm32f103rb-app.hex`
- `stm32f103rb-app.bin`

---

## Flashen

Nucleo per USB anschließen, dann:

```bash
cmake --build --preset debug --target flash
```

Das Flash-Target nutzt OpenOCD mit `board/st_nucleo_f103rb.cfg`.

---

## Debuggen in VS Code

1. Debug-Build ausführen.
2. In Run & Debug die Konfiguration **"STM32F103RB Debug (OpenOCD)"** wählen.
3. Starten, Breakpoints setzen, `main` wird als Entry genutzt.

---

## UART testen

Die Demo sendet bei 115200 Baud:

- Initial: `STM32F103RB libopencm3 C++ startup OK`
- Danach periodisch: `tick`

Auf dem Host den seriellen Port des ST-LINK VCP öffnen (z. B. mit `screen`, `minicom` oder VS Code Serial Monitor).

---

## Nächste sinnvolle Ausbaustufen

- UART RX mit Interrupts/Ringbuffer
- `printf`-Retargeting auf USART2
- Trennung in Board Support Package (BSP) + App-Layer
- Unit-Tests für host-seitige Logik
- Optional FreeRTOS Integration
