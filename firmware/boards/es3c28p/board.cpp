// LCDWIKI ES3C28P (also sold by Hosyond): 2.8" 240x320 IPS on an ESP32-S3
// (16 MB flash, 8 MB PSRAM) with native USB. ILI9341V on SPI, FT6336G
// capacitive touch. The display reset is tied to the chip's own reset.
#include "board.h"
#include "drivers.h"

static const SpiPanelConfig panel = {
    .host = SPI2_HOST,
    .sclk = GPIO_NUM_12, .mosi = GPIO_NUM_11, .miso = GPIO_NUM_13, .cs = GPIO_NUM_10, .dc = GPIO_NUM_46, .rst = GPIO_NUM_NC,
    .pclk_hz = 40000000,
    .spi_mode = 0,
    .bgr = true, .invert = true, .mirror_x = true, .mirror_y = false, .swap_xy = false,
    .init = nullptr,
    .init_len = 0,
};

static i2c_master_bus_handle_t bus;

void board_display_init(int variant) {
  backlight_init(GPIO_NUM_45);
  // Panel batches differ in color inversion; variant bit 0 flips it (set from the app).
  SpiPanelConfig cfg = panel;
  cfg.invert = panel.invert != ((variant & 1) != 0);
  spi_panel_init(cfg, DISP_W, DISP_H);
}

void board_display_draw(int x, int y, int w, int h, const uint16_t *px) {
  spi_panel_draw(x, y, w, h, px);
  g_frames = g_frames + 1;
}

void board_backlight(uint8_t level) { backlight_set(level); }

void board_touch_init(void) {
  // Shared with the audio codec and the I2C socket, which have their own pull-ups.
  bus = i2c_bus_init(GPIO_NUM_16, GPIO_NUM_15, true);
  ft6336_init(bus, GPIO_NUM_18);
}

bool board_touch_read(int16_t *x, int16_t *y) {
  int rx, ry;
  if (!ft6336_read(&rx, &ry)) return false;
  return touch_map({DISP_W, DISP_H, false, false, false}, rx, ry, x, y);
}
