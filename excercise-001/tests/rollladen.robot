# Abnahmetest der Rollladensteuerung in Renode, ohne echte Hardware.
#
# Von Hand starten (aus dem Hauptverzeichnis, nach dem Debug-Build):
#   /opt/renode/renode-test excercise-001/tests/rollladen.robot
#
# Jeder Testfall startet die Firmware neu. Ein Test liest sich wie eine
# Prüfanweisung an der Anlage: Taste drücken, dann Motor prüfen.

*** Variables ***
${ELF}              @${CURDIR}/../../build/debug/excercise-001/rollladen
${REPL}             @${CURDIR}/../renode/rollladen.repl
${UART}             sysbus.usart2

${TASTE_HOCH}       sysbus.gpioPortC.tasteHoch
${TASTE_RUNTER}     sysbus.gpioPortC.tasteRunter
${ES_OBEN}          sysbus.gpioPortC.endschalterOben
${ES_UNTEN}         sysbus.gpioPortC.endschalterUnten
${RELAIS_HOCH}      sysbus.gpioPortB.relaisHoch
${RELAIS_RUNTER}    sysbus.gpioPortB.relaisRunter

*** Keywords ***
Rollladen Einschalten
    Execute Command             mach create
    Execute Command             machine LoadPlatformDescription @platforms/cpus/stm32f103.repl
    Execute Command             machine LoadPlatformDescription ${REPL}
    Execute Command             sysbus LoadELF ${ELF}
    Create Terminal Tester      ${UART}  defaultTimeout=2
    ${hoch}=                    Create LED Tester  ${RELAIS_HOCH}  defaultTimeout=0
    ${runter}=                  Create LED Tester  ${RELAIS_RUNTER}  defaultTimeout=0
    Set Test Variable           ${TESTER_HOCH}  ${hoch}
    Set Test Variable           ${TESTER_RUNTER}  ${runter}
    Start Emulation
    Wait For Line On Uart       Rollladensteuerung gestartet

Zustand Sollte Sein
    [Arguments]                 ${zustand}
    Wait For Line On Uart       Zustand: ${zustand}

Motor Sollte Sein
    [Arguments]                 ${hoch}  ${runter}
    Assert LED State            ${hoch}  testerId=${TESTER_HOCH}
    Assert LED State            ${runter}  testerId=${TESTER_RUNTER}

Betaetigen
    [Documentation]             Taste oder Endschalter drücken und warten,
    ...                         bis die Firmware den neuen Zustand meldet.
    [Arguments]                 ${eingang}  ${erwarteter_zustand}
    Execute Command             ${eingang} Press
    Zustand Sollte Sein         ${erwarteter_zustand}

Loslassen
    [Arguments]                 ${eingang}
    Execute Command             ${eingang} Release

Bis Nach Unten Fahren
    Rollladen Einschalten
    Zustand Sollte Sein         Faehrt runter
    Betaetigen                  ${ES_UNTEN}  Unten

*** Test Cases ***
Faehrt Nach Dem Einschalten Nach Unten
    Rollladen Einschalten
    Zustand Sollte Sein         Faehrt runter
    Motor Sollte Sein           hoch=false  runter=true

Haelt Am Unteren Endschalter
    Bis Nach Unten Fahren
    Motor Sollte Sein           hoch=false  runter=false

Faehrt Hoch Und Haelt Oben
    Bis Nach Unten Fahren
    Betaetigen                  ${TASTE_HOCH}  Faehrt hoch
    Loslassen                   ${TASTE_HOCH}
    Loslassen                   ${ES_UNTEN}
    Motor Sollte Sein           hoch=true  runter=false
    Betaetigen                  ${ES_OBEN}  Oben
    Motor Sollte Sein           hoch=false  runter=false

Wechselt Die Richtung
    Rollladen Einschalten
    Zustand Sollte Sein         Faehrt runter
    Betaetigen                  ${TASTE_HOCH}  Faehrt hoch
    Loslassen                   ${TASTE_HOCH}
    Motor Sollte Sein           hoch=true  runter=false
    Betaetigen                  ${TASTE_RUNTER}  Faehrt runter
    Loslassen                   ${TASTE_RUNTER}
    Motor Sollte Sein           hoch=false  runter=true

Geht Bei Unplausiblem Endschalter In Den Fehlerzustand
    Bis Nach Unten Fahren
    Betaetigen                  ${ES_OBEN}  Fehler
    Motor Sollte Sein           hoch=false  runter=false
    Loslassen                   ${ES_OBEN}
    Execute Command             ${TASTE_HOCH} Press
    Motor Sollte Sein           hoch=false  runter=false
