/**
 * @file board.cpp
 * @brief Hardwarezugriffe mit libopencm3.
 */
#include "board.h"

#include <libopencm3/stm32/gpio.h>
#include <libopencm3/stm32/rcc.h>
#include <libopencm3/stm32/usart.h>

namespace {

/* Eingänge: alle an Port C, Pins 0..3 in der Reihenfolge von enum Ereignis */
constexpr uint32_t kEingangPort = GPIOC;
constexpr uint16_t kEingangPins = GPIO0 | GPIO1 | GPIO2 | GPIO3;

/* Ausgänge */
constexpr uint32_t kRelaisPort = GPIOB;
constexpr uint16_t kRelaisHoch = GPIO8;   // K1
constexpr uint16_t kRelaisRunter = GPIO9; // K2
constexpr uint32_t kLedPort = GPIOA;
constexpr uint16_t kLedPin = GPIO5;       // LD2

/* UART: USART2 an PA2 (TX) */
constexpr uint32_t kUartPort = GPIOA;
constexpr uint16_t kUartTxPin = GPIO2;

void takt_einrichten()
{
    /* Internen HSI-Oszillator nutzen: läuft in Renode zuverlässig */
    rcc_clock_setup_pll(&rcc_hsi_configs[RCC_CLOCK_HSI_48MHZ]);
    rcc_periph_clock_enable(RCC_GPIOA);
    rcc_periph_clock_enable(RCC_GPIOB);
    rcc_periph_clock_enable(RCC_GPIOC);
    rcc_periph_clock_enable(RCC_USART2);
}

void gpios_einrichten()
{
    /* Eingänge mit Pull-up: Beim F1 wählt das ODR-Bit zwischen Pull-up (1)
     * und Pull-down (0). Ein betätigter Taster zieht den Pin auf 0. */
    gpio_set_mode(kEingangPort, GPIO_MODE_INPUT, GPIO_CNF_INPUT_PULL_UPDOWN, kEingangPins);
    gpio_set(kEingangPort, kEingangPins);

    /* Relais zuerst ausschalten, dann als Ausgang schalten */
    gpio_clear(kRelaisPort, kRelaisHoch | kRelaisRunter);
    gpio_set_mode(kRelaisPort, GPIO_MODE_OUTPUT_2_MHZ, GPIO_CNF_OUTPUT_PUSHPULL,
                  kRelaisHoch | kRelaisRunter);

    gpio_clear(kLedPort, kLedPin);
    gpio_set_mode(kLedPort, GPIO_MODE_OUTPUT_2_MHZ, GPIO_CNF_OUTPUT_PUSHPULL, kLedPin);

    gpio_set_mode(kUartPort, GPIO_MODE_OUTPUT_50_MHZ, GPIO_CNF_OUTPUT_ALTFN_PUSHPULL, kUartTxPin);
}

void uart_einrichten()
{
    usart_set_baudrate(USART2, 115200);
    usart_set_databits(USART2, 8);
    usart_set_stopbits(USART2, USART_STOPBITS_1);
    usart_set_mode(USART2, USART_MODE_TX);
    usart_set_parity(USART2, USART_PARITY_NONE);
    usart_set_flow_control(USART2, USART_FLOWCONTROL_NONE);
    usart_enable(USART2);
}

} // namespace

void board_init()
{
    takt_einrichten();
    gpios_einrichten();
    uart_einrichten();
}

uint8_t board_eingaenge_lesen()
{
    /* Aktiv low: gelesene 0 heißt "betätigt". Deshalb invertieren. */
    const uint16_t pegel = gpio_get(kEingangPort, kEingangPins);
    const uint16_t betaetigt = static_cast<uint16_t>(~pegel) & kEingangPins;
    return static_cast<uint8_t>(betaetigt); // PC0..PC3 sind schon Bit 0..3
}

void board_motor_setzen(Motor motor)
{
    /* Verriegelung wie bei Wendeschützen: erst beide Relais aus, dann
     * höchstens eines ein. So sind nie beide gleichzeitig an. */
    gpio_clear(kRelaisPort, kRelaisHoch | kRelaisRunter);

    if (motor == MOTOR_HOCH) {
        gpio_set(kRelaisPort, kRelaisHoch);
    } else if (motor == MOTOR_RUNTER) {
        gpio_set(kRelaisPort, kRelaisRunter);
    }

    /* LED leuchtet, solange der Motor läuft */
    if (motor == MOTOR_AUS) {
        gpio_clear(kLedPort, kLedPin);
    } else {
        gpio_set(kLedPort, kLedPin);
    }
}

void board_text_senden(const char *text)
{
    while (*text != '\0') {
        usart_send_blocking(USART2, static_cast<uint16_t>(*text));
        ++text;
    }
}
