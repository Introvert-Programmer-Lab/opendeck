// Display, touch and backlight drivers shared by the board files. A board
// lists the ones it uses in BOARD_DRIVERS (board.cmake) and fills in the
// config structs with its pins.
#pragma once
#include <stdint.h>
#include <stddef.h>
#include "driver/gpio.h"
#include "driver/i2c_master.h"
#include "driver/spi_master.h"

// One panel command with its parameters, for vendor init sequences.
struct LcdCmd {
  uint8_t cmd;
  uint8_t len;
  uint8_t data[16];
  uint16_t delay_ms;
};

// backlight.cpp: PWM on the backlight pin.
void backlight_init(gpio_num_t pin, bool active_high = true);
void backlight_set(uint8_t level);

// panel_spi.cpp: MIPI DCS panels on SPI (ILI9341, ST7789, ST7796).
struct SpiPanelConfig {
  spi_host_device_t host;
  gpio_num_t sclk, mosi, miso, cs, dc, rst;
  int pclk_hz;
  int spi_mode;
  bool bgr;         // panel expects BGR order
  bool invert;      // IPS panels usually need color inversion
  bool mirror_x, mirror_y, swap_xy;
  const LcdCmd *init;  // extra vendor commands sent after reset, may be null
  size_t init_len;
};
void spi_panel_init(const SpiPanelConfig &cfg, int width, int height);
void spi_panel_draw(int x, int y, int w, int h, const uint16_t *px);

// panel_rgb.cpp: 16-bit parallel RGB panels (ESP32-S3 only).
struct RgbPanelConfig {
  gpio_num_t pclk, hsync, vsync, de;
  gpio_num_t data[16];  // B0..B4, G0..G5, R0..R4
  uint32_t pclk_hz;
  uint16_t hsync_pulse, hsync_back, hsync_front;
  uint16_t vsync_pulse, vsync_back, vsync_front;
  bool hsync_idle_low, vsync_idle_low, pclk_active_neg;
};
void rgb_panel_init(const RgbPanelConfig &cfg, int width, int height);
void rgb_panel_draw(int x, int y, int w, int h, const uint16_t *px);

// st7701_3wire.cpp: ST7701 controllers take their init sequence over a 3-wire
// 9-bit SPI before the RGB bus starts.
void st7701_send_init(gpio_num_t cs, gpio_num_t sck, gpio_num_t sda, const LcdCmd *cmds, size_t n);

// panel_qspi.cpp: QSPI panels with 0x02/0x32 command framing (NV3041A).
struct QspiPanelConfig {
  spi_host_device_t host;
  gpio_num_t sclk, d0, d1, d2, d3, cs, rst;
  int pclk_hz;
  const LcdCmd *init;
  size_t init_len;
};
void qspi_panel_init(const QspiPanelConfig &cfg, int width, int height);
void qspi_panel_draw(int x, int y, int w, int h, const uint16_t *px);

// i2c_bus.cpp
i2c_master_bus_handle_t i2c_bus_init(gpio_num_t sda, gpio_num_t scl, bool pullups);

// Maps raw touch coordinates onto the panel.
struct TouchMap {
  int width, height;  // panel size
  bool swap_xy, mirror_x, mirror_y;
};
inline bool touch_map(const TouchMap &m, int rx, int ry, int16_t *x, int16_t *y) {
  if (m.swap_xy) {
    int t = rx;
    rx = ry;
    ry = t;
  }
  if (m.mirror_x) rx = m.width - 1 - rx;
  if (m.mirror_y) ry = m.height - 1 - ry;
  if (rx < 0 || ry < 0 || rx >= m.width || ry >= m.height) return false;
  *x = rx;
  *y = ry;
  return true;
}

// touch_gt911.cpp (I2C 0x5D or 0x14)
void gt911_init(i2c_master_bus_handle_t bus, gpio_num_t rst, gpio_num_t irq);
bool gt911_read(int *x, int *y);

// touch_cst816.cpp (I2C 0x15)
void cst816_init(i2c_master_bus_handle_t bus, gpio_num_t rst);
bool cst816_read(int *x, int *y);

// touch_ft6336.cpp (I2C 0x38)
void ft6336_init(i2c_master_bus_handle_t bus, gpio_num_t rst);
bool ft6336_read(int *x, int *y);

// touch_xpt2046.cpp: resistive controller on SPI. Raw readings are scaled to
// the panel with a fixed calibration that suits the common boards.
struct Xpt2046Config {
  spi_host_device_t host;
  bool own_bus;  // false: shares the display's bus, already initialised
  gpio_num_t sclk, mosi, miso, cs;
  int raw_min_x, raw_max_x, raw_min_y, raw_max_y;
};
void xpt2046_init(const Xpt2046Config &cfg);
// x, y in 0..4095 after calibration scaling to [0, 4096).
bool xpt2046_read(int *x, int *y);
