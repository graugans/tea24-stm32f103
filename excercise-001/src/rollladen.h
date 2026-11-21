/**
 * @file rollladen.h
 * @brief Zustandsautomat der Rollladensteuerung.
 *
 * Diese Datei kennt keine Hardware. Sie beschreibt nur die Logik:
 * Welcher Zustand folgt auf welches Ereignis, und was macht der Motor
 * in welchem Zustand?
 */
#pragma once

#include <cstdint>

/* Die Zustände des Rollladens. Die Reihenfolge ist zugleich die
 * Zeilennummer in der Übergangstabelle. */
enum Zustand : uint8_t {
    ZUSTAND_FAEHRT_RUNTER, // Startzustand: Position unbekannt, erst nach unten
    ZUSTAND_UNTEN,
    ZUSTAND_FAEHRT_HOCH,
    ZUSTAND_OBEN,
    ZUSTAND_FEHLER,        // unplausibler Endschalter: Motor aus, nur Reset hilft
    ANZAHL_ZUSTAENDE       // kein echter Zustand, nur die Anzahl
};

/* Die Ereignisse. Die Reihenfolge ist zugleich die Spaltennummer in der
 * Übergangstabelle und die Bitnummer in board_eingaenge_lesen(). */
enum Ereignis : uint8_t {
    EREIGNIS_TASTE_HOCH,
    EREIGNIS_TASTE_RUNTER,
    EREIGNIS_ENDSCHALTER_OBEN,
    EREIGNIS_ENDSCHALTER_UNTEN,
    ANZAHL_EREIGNISSE,                     // kein echtes Ereignis
    EREIGNIS_KEINS = ANZAHL_EREIGNISSE     // "nichts passiert"
};

/* Was der Motor tun soll. */
enum Motor : uint8_t {
    MOTOR_AUS,
    MOTOR_HOCH,
    MOTOR_RUNTER
};

constexpr Zustand START_ZUSTAND = ZUSTAND_FAEHRT_RUNTER;

/* Liefert den Folgezustand. Ein unbekanntes Ereignis ändert nichts. */
Zustand rollladen_naechster_zustand(Zustand aktuell, Ereignis ereignis);

/* Liefert, was der Motor im Zustand tun soll (Moore-Automat). */
Motor rollladen_motor(Zustand zustand);

/* Liefert einen lesbaren Namen für die Ausgabe über die UART. */
const char *rollladen_name(Zustand zustand);
