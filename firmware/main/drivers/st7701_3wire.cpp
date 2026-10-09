// ST7701 init over its 3-wire SPI: each byte goes out as 9 bits, the first
// one telling command (0) from data (1). Bit-banged: it runs once at boot.
#include "drivers.h"
#include "esp_rom_sys.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static gpio_num_t pin_sck, pin_sda;

static void bit(int v) {
  gpio_set_level(pin_sda, v);
  esp_rom_delay_us(1);
  gpio_set_level(pin_sck, 1);
  esp_rom_delay_us(1);
  gpio_set_level(pin_sck, 0);
}

static void word9(bool data, uint8_t b) {
  bit(data);
  for (int i = 7; i >= 0; i--) bit((b >> i) & 1);
}

void st7701_send_init(gpio_num_t cs, gpio_num_t sck, gpio_num_t sda, const LcdCmd *cmds, size_t n) {
  pin_sck = sck;
  pin_sda = sda;
  const gpio_num_t pins[] = {cs, sck, sda};
  for (gpio_num_t p : pins) {
    gpio_reset_pin(p);
    gpio_set_direction(p, GPIO_MODE_OUTPUT);
  }
  gpio_set_level(cs, 1);
  gpio_set_level(sck, 0);
  for (size_t i = 0; i < n; i++) {
    gpio_set_level(cs, 0);
    word9(false, cmds[i].cmd);
    for (int j = 0; j < cmds[i].len; j++) word9(true, cmds[i].data[j]);
    gpio_set_level(cs, 1);
    if (cmds[i].delay_ms) vTaskDelay(pdMS_TO_TICKS(cmds[i].delay_ms));
  }
}
