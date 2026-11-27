/**
 * @file eingaben.h
 * @brief Aus Eingangspegeln Ereignisse machen (Flankenerkennung).
 */
#pragma once

#include <cstdint>

#include "rollladen.h"

/*
 * Bekommt den aktuellen Zustand aller Eingänge als Bitmuster
 * (Bit 0 = Taste hoch, Bit 1 = Taste runter, ... wie enum Ereignis;
 * 1 = betätigt) und liefert das Ereignis eines Eingangs, der seit dem
 * letzten Aufruf NEU betätigt wurde. Sonst EREIGNIS_KEINS.
 *
 * Wer eine Taste gedrückt hält, löst also nur ein Ereignis aus.
 */
Ereignis eingaben_auswerten(uint8_t eingaenge);
