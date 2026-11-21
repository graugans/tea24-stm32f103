# Übungsaufgabe 001: Rollladensteuerung mit Zustandsautomat
#
# Wird vom CMakeLists.txt im Hauptverzeichnis per add_subdirectory()
# eingebunden. Linker-Script, Start-up-Code und libopencm3 kommen von dort.

set(ROLLLADEN_TARGET rollladen)

add_executable(${ROLLLADEN_TARGET}
    src/main.cpp
    src/board.cpp
    src/eingaben.cpp
    src/rollladen.cpp
    ${CMAKE_SOURCE_DIR}/src/startup_stm32f103rb.c
    ${CMAKE_SOURCE_DIR}/src/syscalls.c
)

target_include_directories(${ROLLLADEN_TARGET} PRIVATE ${LIBOPENCM3_DIR}/include)
target_compile_definitions(${ROLLLADEN_TARGET} PRIVATE STM32F1)

target_compile_options(${ROLLLADEN_TARGET}
    PRIVATE
        -mcpu=cortex-m3
        -mthumb
        -ffunction-sections
        -fdata-sections
        -fno-common
        -Wall
        -Wextra
        -Wpedantic
        $<$<COMPILE_LANGUAGE:CXX>:-fno-exceptions>
        $<$<COMPILE_LANGUAGE:CXX>:-fno-rtti>
        $<$<COMPILE_LANGUAGE:CXX>:-fno-threadsafe-statics>
)

target_link_options(${ROLLLADEN_TARGET}
    PRIVATE
        -mcpu=cortex-m3
        -mthumb
        -T${LINKER_SCRIPT}
        -Wl,--gc-sections
        -Wl,-Map=${ROLLLADEN_TARGET}.map
        -Wl,--print-memory-usage
        --specs=nosys.specs
)

target_link_libraries(${ROLLLADEN_TARGET} PRIVATE ${LIBOPENCM3_LIBRARY})
add_dependencies(${ROLLLADEN_TARGET} libopencm3_build)

# ---------------------------------------------------------------------------
# Tests (ausführen mit: ctest --test-dir build/debug --output-on-failure)
# ---------------------------------------------------------------------------

# Liegt die Übergangstabelle wirklich in .rodata (Flash)? Prüft arm-none-eabi-nm.
add_test(
    NAME rollladen_tabelle_in_rodata
    COMMAND ${CMAKE_COMMAND}
        -DNM=${CMAKE_NM}
        -DELF=$<TARGET_FILE:${ROLLLADEN_TARGET}>
        -DSYMBOL=uebergangstabelle
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/check_rodata.cmake
)

# Verhalten in Renode prüfen. Braucht Robot Framework, das (noch) nicht im
# Dev-Container installiert ist. Deshalb nur auf Wunsch:
#   cmake --preset debug -DROLLLADEN_ROBOT_TESTS=ON
option(ROLLLADEN_ROBOT_TESTS "Robot-Framework-Tests in Renode ausführen" OFF)
if(ROLLLADEN_ROBOT_TESTS)
    find_program(RENODE_TEST renode-test HINTS /opt/renode REQUIRED)
    add_test(
        NAME rollladen_renode_robot
        COMMAND ${RENODE_TEST}
            --variable ELF:@$<TARGET_FILE:${ROLLLADEN_TARGET}>
            --variable REPL:@${CMAKE_CURRENT_SOURCE_DIR}/renode/rollladen.repl
            ${CMAKE_CURRENT_SOURCE_DIR}/tests/rollladen.robot
    )
endif()
