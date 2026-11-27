/**
 * @file board.h
 * @brief Alles, was mit der Hardware des Nucleo-F103RB zu tun hat.
 *
 * Belegung (gedanklich, wie an einer echten Anlage):
 *
 *   Eingänge (Port C, aktiv low mit Pull-up, wie der Taster B1 auf dem Nucleo)
 *     PC0  Taste hoch
 *     PC1  Taste runter
 *     PC2  Endschalter oben
 *     PC3  Endschalter unten
 *
 *   Ausgänge
 *     PB8  Relais K1: Motor hoch
 *     PB9  Relais K2: Motor runter
 *     PA5  LED LD2:   Motor läuft
 *     PA2  USART2 TX: Statusmeldungen (ST-LINK Virtual COM Port, 115200 Baud)
 */
#pragma once

#include <cstdint>

#include "rollladen.h"

/* Takt, GPIOs und UART einrichten. Danach sind beide Relais aus. */
void board_init();

/* Liest alle vier Eingänge. Bitnummer wie enum Ereignis, 1 = betätigt. */
uint8_t board_eingaenge_lesen();

/* Schaltet die Relais. Es ist nie mehr als ein Relais an. */
void board_motor_setzen(Motor motor);

/* Gibt einen Text über die UART aus. */
void board_text_senden(const char *text);
