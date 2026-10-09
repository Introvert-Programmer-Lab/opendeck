// Hynitron CST816S / CST820 capacitive touch controller (I2C 0x15).
#include "drivers.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static i2c_master_dev_handle_t dev;

void cst816_init(i2c_master_bus_handle_t bus, gpio_num_t rst) {
  if (rst != GPIO_NUM_NC) {
    gpio_set_direction(rst, GPIO_MODE_OUTPUT);
    gpio_set_level(rst, 0);
    vTaskDelay(pdMS_TO_TICKS(10));
    gpio_set_level(rst, 1);
    vTaskDelay(pdMS_TO_TICKS(60));
  }
  i2c_device_config_t cfg = {};
  cfg.dev_addr_length = I2C_ADDR_BIT_LEN_7;
  cfg.device_address = 0x15;
  cfg.scl_speed_hz = 400000;
  i2c_master_bus_add_device(bus, &cfg, &dev);
  // Keep the controller awake; it otherwise stops answering after a few seconds.
  uint8_t no_sleep[2] = {0xFE, 0x01};
  i2c_master_transmit(dev, no_sleep, 2, 50);
}

bool cst816_read(int *x, int *y) {
  uint8_t reg = 0x02;
  uint8_t d[5];
  if (!dev || i2c_master_transmit_receive(dev, &reg, 1, d, 5, 50) != ESP_OK) return false;
  if ((d[0] & 0x0F) == 0) return false;
  *x = ((d[1] & 0x0F) << 8) | d[2];
  *y = ((d[3] & 0x0F) << 8) | d[4];
  return true;
}
