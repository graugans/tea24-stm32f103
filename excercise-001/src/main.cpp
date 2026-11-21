/**
 * @file main.cpp
 * @brief Rollladensteuerung: Hauptschleife.
 *
 * Die Arbeit ist auf drei Module verteilt:
 *   board.cpp     Hardware (GPIO, Relais, UART)
 *   eingaben.cpp  aus Pegeln werden Ereignisse
 *   rollladen.cpp der Zustandsautomat mit der Übergangstabelle
 */
#include "board.h"
#include "eingaben.h"
#include "rollladen.h"

namespace {

/* Ausgänge zum Zustand setzen und den Zustand melden */
void zustand_ausgeben(Zustand zustand)
{
    board_motor_setzen(rollladen_motor(zustand));
    board_text_senden("Zustand: ");
    board_text_senden(rollladen_name(zustand));
    board_text_senden("\r\n");
}

} // namespace

extern "C" int main()
{
    board_init();
    board_text_senden("Rollladensteuerung gestartet\r\n");

    Zustand zustand = START_ZUSTAND;
    zustand_ausgeben(zustand);

    while (true) {
        const Ereignis ereignis = eingaben_auswerten(board_eingaenge_lesen());
        if (ereignis == EREIGNIS_KEINS) {
            continue; // nichts passiert, weiter abfragen
        }

        const Zustand neu = rollladen_naechster_zustand(zustand, ereignis);
        if (neu != zustand) {
            zustand = neu;
            zustand_ausgeben(zustand);
        }
    }
}
