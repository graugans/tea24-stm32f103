# Prüft mit nm, ob ein konstantes Symbol im Flash liegt und nicht im RAM.
#
# Aufruf: cmake -DNM=<nm> -DELF=<datei> -DSYMBOL=<name> -P check_rodata.cmake
#
# nm zeigt für jedes Symbol Adresse und einen Buchstaben für den Abschnitt:
#   R/r  .rodata  konstante Daten im Flash
#   T/t  .text    Code im Flash. Unser Linker-Script legt .rodata mit in den
#                 Ausgabeabschnitt .text, deshalb erscheint die Tabelle so.
#   D/d  .data    Startwert im Flash UND Platz im RAM
#   B/b  .bss     RAM, beim Start mit 0 gefüllt
# Großbuchstabe = global sichtbar, Kleinbuchstabe = nur in seiner Datei.
#
# Entscheidend ist deshalb die Adresse: Flash beginnt bei 0x08000000,
# RAM bei 0x20000000.

execute_process(
    COMMAND ${NM} --demangle ${ELF}
    OUTPUT_VARIABLE symbole
    RESULT_VARIABLE fehler
)
if(fehler)
    message(FATAL_ERROR "nm konnte ${ELF} nicht lesen")
endif()

string(REGEX MATCH "([0-9a-fA-F]+) ([A-Za-z]) [^\n]*${SYMBOL}\n" treffer "${symbole}")
if(NOT treffer)
    message(FATAL_ERROR "Symbol '${SYMBOL}' nicht gefunden. Wurde es umbenannt?")
endif()

set(adresse "${CMAKE_MATCH_1}")
set(typ "${CMAKE_MATCH_2}")

if(adresse MATCHES "^08" AND typ MATCHES "^[RrTt]$")
    message(STATUS "OK: '${SYMBOL}' liegt im Flash (Adresse 0x${adresse}, nm-Typ ${typ})")
else()
    message(FATAL_ERROR
        "'${SYMBOL}' liegt NICHT nur im Flash: Adresse 0x${adresse}, nm-Typ '${typ}'.\n"
        "Fehlt das 'const' bei der Tabelle? Dann landet sie in .data: Der "
        "Start-up-Code kopiert sie beim Start ins RAM, und sie belegt dort Platz.")
endif()
