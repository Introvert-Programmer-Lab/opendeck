// Goodix GT911 capacitive touch controller.
#include "drivers.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static i2c_master_dev_handle_t dev;

static bool reg_read(uint16_t reg, uint8_t *out, size_t n) {
  uint8_t addr[2] = {(uint8_t)(reg >> 8), (uint8_t)reg};
  return i2c_master_transmit_receive(dev, addr, 2, out, n, 50) == ESP_OK;
}

static void reg_write(uint16_t reg, uint8_t v) {
  uint8_t buf[3] = {(uint8_t)(reg >> 8), (uint8_t)reg, v};
  i2c_master_transmit(dev, buf, 3, 50);
}

void gt911_init(i2c_master_bus_handle_t bus, gpio_num_t rst, gpio_num_t irq) {
  // With a reset line, holding INT low during reset selects address 0x5D.
  if (rst != GPIO_NUM_NC) {
    gpio_set_direction(rst, GPIO_MODE_OUTPUT);
    if (irq != GPIO_NUM_NC) {
      gpio_set_direction(irq, GPIO_MODE_OUTPUT);
      gpio_set_level(irq, 0);
    }
    gpio_set_level(rst, 0);
    vTaskDelay(pdMS_TO_TICKS(10));
    gpio_set_level(rst, 1);
    vTaskDelay(pdMS_TO_TICKS(60));
    if (irq != GPIO_NUM_NC) gpio_set_direction(irq, GPIO_MODE_INPUT);
  }
  uint16_t addr = i2c_master_probe(bus, 0x5D, 50) == ESP_OK ? 0x5D : 0x14;
  i2c_device_config_t cfg = {};
  cfg.dev_addr_length = I2C_ADDR_BIT_LEN_7;
  cfg.device_address = addr;
  cfg.scl_speed_hz = 400000;
  i2c_master_bus_add_device(bus, &cfg, &dev);
}

bool gt911_read(int *x, int *y) {
  uint8_t status;
  if (!dev || !reg_read(0x814E, &status, 1)) return false;
  if (!(status & 0x80)) return false;  // no new data yet
  bool down = false;
  if ((status & 0x0F) > 0) {
    uint8_t p[4];
    if (reg_read(0x8150, p, 4)) {
      *x = p[0] | (p[1] << 8);
      *y = p[2] | (p[3] << 8);
      down = true;
    }
  }
  reg_write(0x814E, 0);
  return down;
}
