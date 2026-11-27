/**
 * @file rollladen.cpp
 * @brief Zustandsautomat als Übergangstabelle.
 */
#include "rollladen.h"

namespace {

/*
 * Die Übergangstabelle: Zeile = aktueller Zustand, Spalte = Ereignis,
 * Inhalt = Folgezustand.
 *
 * Wichtig ist das "const": Damit legt der Linker die Tabelle in .rodata,
 * also in den Flash. Ohne "const" landet sie in .data und belegt zusätzlich
 * RAM. Der CTest "rollladen_tabelle_in_rodata" prüft das.
 */
const Zustand uebergangstabelle[ANZAHL_ZUSTAENDE][ANZAHL_EREIGNISSE] = {
    //                    TASTE_HOCH           TASTE_RUNTER           ENDSCHALTER_OBEN       ENDSCHALTER_UNTEN
    /* FAEHRT_RUNTER */ { ZUSTAND_FAEHRT_HOCH, ZUSTAND_FAEHRT_RUNTER, ZUSTAND_FAEHRT_RUNTER, ZUSTAND_UNTEN       },
    /* UNTEN         */ { ZUSTAND_FAEHRT_HOCH, ZUSTAND_UNTEN,         ZUSTAND_FEHLER,        ZUSTAND_UNTEN       },
    /* FAEHRT_HOCH   */ { ZUSTAND_FAEHRT_HOCH, ZUSTAND_FAEHRT_RUNTER, ZUSTAND_OBEN,          ZUSTAND_FEHLER      },
    /* OBEN          */ { ZUSTAND_OBEN,        ZUSTAND_FAEHRT_RUNTER, ZUSTAND_OBEN,          ZUSTAND_FEHLER      },
    /* FEHLER        */ { ZUSTAND_FEHLER,      ZUSTAND_FEHLER,        ZUSTAND_FEHLER,        ZUSTAND_FEHLER      },
};

/*
 * Warum FAEHRT_RUNTER + ENDSCHALTER_OBEN kein Fehler ist: Nach dem
 * Einschalten ist die Position unbekannt. Steht der Rollladen oben, meldet
 * der obere Endschalter beim ersten Abfragen "betätigt". Das ist plausibel.
 *
 * Alle anderen Endschalter, die nicht zur Fahrtrichtung passen, deuten auf
 * einen Defekt hin (Kabelbruch, verklemmter Schalter, vertauschte Adern).
 * Dann hält die Steuerung den Motor an und bleibt im Fehlerzustand, bis
 * jemand nachsieht und neu startet.
 */

/* Ausgang je Zustand, ebenfalls als Tabelle im Flash. */
const Motor motor_je_zustand[ANZAHL_ZUSTAENDE] = {
    /* FAEHRT_RUNTER */ MOTOR_RUNTER,
    /* UNTEN         */ MOTOR_AUS,
    /* FAEHRT_HOCH   */ MOTOR_HOCH,
    /* OBEN          */ MOTOR_AUS,
    /* FEHLER        */ MOTOR_AUS,
};

/* Namen je Zustand. Beide "const" sind nötig: Zeiger UND Text liegen im Flash. */
const char *const name_je_zustand[ANZAHL_ZUSTAENDE] = {
    "Faehrt runter",
    "Unten",
    "Faehrt hoch",
    "Oben",
    "Fehler",
};

} // namespace

Zustand rollladen_naechster_zustand(Zustand aktuell, Ereignis ereignis)
{
    /* Schutz vor einem Zugriff außerhalb der Tabelle */
    if (aktuell >= ANZAHL_ZUSTAENDE || ereignis >= ANZAHL_EREIGNISSE) {
        return aktuell;
    }
    return uebergangstabelle[aktuell][ereignis];
}

Motor rollladen_motor(Zustand zustand)
{
    if (zustand >= ANZAHL_ZUSTAENDE) {
        return MOTOR_AUS; // im Zweifel anhalten
    }
    return motor_je_zustand[zustand];
}

const char *rollladen_name(Zustand zustand)
{
    if (zustand >= ANZAHL_ZUSTAENDE) {
        return "?";
    }
    return name_je_zustand[zustand];
}
