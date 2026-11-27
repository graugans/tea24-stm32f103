/**
 * @file eingaben.cpp
 * @brief Flankenerkennung: aus "ist gedrückt" wird "wurde gerade gedrückt".
 */
#include "eingaben.h"

Ereignis eingaben_auswerten(uint8_t eingaenge)
{
    /*
     * Merker: Welche Eingänge wurden schon als Ereignis gemeldet?
     * "static" heißt: Die Variable behält ihren Wert zwischen den Aufrufen
     * und liegt in .bss. Startwert 0 bedeutet: Ist beim Einschalten schon
     * ein Endschalter betätigt, wird das beim ersten Aufruf gemeldet.
     */
    static uint8_t gemeldet = 0;

    /* Losgelassene Eingänge vergessen, damit sie erneut auslösen können */
    gemeldet = gemeldet & eingaenge;

    /* Neu betätigt = jetzt betätigt, aber noch nicht gemeldet */
    const uint8_t neu = eingaenge & static_cast<uint8_t>(~gemeldet);

    /* Pro Aufruf nur EIN Ereignis melden, die anderen kommen beim nächsten Mal */
    for (uint8_t i = 0; i < ANZAHL_EREIGNISSE; i++) {
        const uint8_t bit = static_cast<uint8_t>(1U << i);
        if ((neu & bit) != 0U) {
            gemeldet = gemeldet | bit;
            return static_cast<Ereignis>(i);
        }
    }
    return EREIGNIS_KEINS;
}
