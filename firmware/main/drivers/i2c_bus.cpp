#include "drivers.h"

i2c_master_bus_handle_t i2c_bus_init(gpio_num_t sda, gpio_num_t scl, bool pullups) {
  i2c_master_bus_config_t cfg = {};
  cfg.i2c_port = I2C_NUM_0;
  cfg.sda_io_num = sda;
  cfg.scl_io_num = scl;
  cfg.clk_source = I2C_CLK_SRC_DEFAULT;
  cfg.glitch_ignore_cnt = 7;
  cfg.flags.enable_internal_pullup = pullups;
  i2c_master_bus_handle_t bus = nullptr;
  i2c_new_master_bus(&cfg, &bus);
  return bus;
}
