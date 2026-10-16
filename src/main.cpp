#include <libopencm3/cm3/systick.h>
#include <libopencm3/stm32/gpio.h>
#include <libopencm3/stm32/rcc.h>
#include <libopencm3/stm32/usart.h>

namespace {

constexpr uint32_t kLedPort = GPIOA;
constexpr uint16_t kLedPin = GPIO5;    // Nucleo LD2
constexpr uint32_t kUartPort = GPIOA;
constexpr uint16_t kUartTxPin = GPIO2; // USART2_TX (ST-LINK VCP)
constexpr uint16_t kUartRxPin = GPIO3; // USART2_RX (ST-LINK VCP)

volatile uint32_t system_millis = 0;

extern "C" void sys_tick_handler(void)
{
    system_millis = system_millis + 1;
}

void clock_setup()
{
    rcc_clock_setup_pll(&rcc_hse_configs[RCC_CLOCK_HSE8_72MHZ]);
    rcc_periph_clock_enable(RCC_GPIOA);
    rcc_periph_clock_enable(RCC_USART2);
}

void gpio_setup()
{
    gpio_set_mode(kLedPort, GPIO_MODE_OUTPUT_2_MHZ, GPIO_CNF_OUTPUT_PUSHPULL, kLedPin);
    gpio_set_mode(kUartPort, GPIO_MODE_OUTPUT_50_MHZ, GPIO_CNF_OUTPUT_ALTFN_PUSHPULL, kUartTxPin);
    gpio_set_mode(kUartPort, GPIO_MODE_INPUT, GPIO_CNF_INPUT_FLOAT, kUartRxPin);
}

void uart_setup()
{
    usart_set_baudrate(USART2, 115200);
    usart_set_databits(USART2, 8);
    usart_set_stopbits(USART2, USART_STOPBITS_1);
    usart_set_mode(USART2, USART_MODE_TX_RX);
    usart_set_parity(USART2, USART_PARITY_NONE);
    usart_set_flow_control(USART2, USART_FLOWCONTROL_NONE);
    usart_enable(USART2);
}

void systick_setup()
{
    systick_set_clocksource(STK_CSR_CLKSOURCE_AHB_DIV8);
    systick_set_reload(9000 - 1); // 72 MHz / 8 / 9000 = 1 kHz
    systick_interrupt_enable();
    systick_counter_enable();
}

void uart_write(const char *text)
{
    while (*text != '\0') {
        usart_send_blocking(USART2, static_cast<uint16_t>(*text));
        ++text;
    }
}

void delay_ms(uint32_t delay)
{
    const uint32_t target = system_millis + delay;
    while (system_millis < target) {
    }
}

} // namespace

extern "C" int main()
{
    clock_setup();
    gpio_setup();
    uart_setup();
    systick_setup();

    uart_write("STM32F103RB libopencm3 C++ startup OK\r\n");

    while (true) {
        gpio_toggle(kLedPort, kLedPin);
        uart_write("tick\r\n");
        delay_ms(500);
    }
}
