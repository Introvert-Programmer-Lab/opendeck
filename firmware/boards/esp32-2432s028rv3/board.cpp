// Sunton ESP32-2432S028R ("Cheap Yellow Display"), third revision with a ST7789 panel.
// Classic ESP32 (no PSRAM, so the screen is drawn in bands), 240x320 ST7789
// on SPI, XPT2046 resistive touch, USB-UART bridge.
#include "board.h"
#include "drivers.h"

static const SpiPanelConfig panel = {
    .host = SPI2_HOST,
    .sclk = GPIO_NUM_14, .mosi = GPIO_NUM_13, .miso = GPIO_NUM_NC, .cs = GPIO_NUM_15, .dc = GPIO_NUM_2, .rst = GPIO_NUM_NC,
    .pclk_hz = 40000000,
    .spi_mode = 3,
    .bgr = false, .invert = false, .mirror_x = false, .mirror_y = false, .swap_xy = false,
    .init = nullptr,
    .init_len = 0,
};

static const Xpt2046Config touch = {
    .host = SPI3_HOST,
    .own_bus = true,
    .sclk = GPIO_NUM_25, .mosi = GPIO_NUM_32, .miso = GPIO_NUM_39, .cs = GPIO_NUM_33,
    .raw_min_x = 200, .raw_max_x = 3700, .raw_min_y = 240, .raw_max_y = 3800,
};

void board_display_init(int variant) {
  backlight_init(GPIO_NUM_21);
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
  xpt2046_init(touch);
}

bool board_touch_read(int16_t *x, int16_t *y) {
  int rx, ry;
  if (!xpt2046_read(&rx, &ry)) return false;
  // The controller's X axis runs along the panel's long side.
  return touch_map({DISP_W, DISP_H, false, true, false}, ry * DISP_W / 4096, rx * DISP_H / 4096, x, y);
}
