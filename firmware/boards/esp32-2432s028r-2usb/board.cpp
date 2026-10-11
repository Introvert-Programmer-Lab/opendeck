// Sunton ESP32-2432S028R with two USB ports (USB-C + micro-USB), the "CYD2USB".
// Same pins as the original R, but a ST7789 panel instead of the ILI9341
// (BGR, inversion off, the gamma curve reset below), its MISO wired to GPIO12,
// and the touch film's axes running the other way. Reported in issue #1.
// Note: its USB-C port has no CC resistors, so use a USB-A to C cable (or the
// micro-USB port); C-to-C cables won't power it.
#include "board.h"
#include "drivers.h"

// Gamma curve reset (select curve 2, then curve 1): the panels ship with a washed-out
// curve until this is sent. Same fix as the community CYD2USB setup for TFT_eSPI.
static const LcdCmd vendor_init[] = {
    {0x26, 1, {0x02}, 120},
    {0x26, 1, {0x01}, 0},
};

static const SpiPanelConfig panel = {
    .host = SPI2_HOST,
    .sclk = GPIO_NUM_14, .mosi = GPIO_NUM_13, .miso = GPIO_NUM_12, .cs = GPIO_NUM_15, .dc = GPIO_NUM_2, .rst = GPIO_NUM_NC,
    .pclk_hz = 40000000,
    .spi_mode = 0,
    .bgr = true, .invert = false, .mirror_x = true, .mirror_y = false, .swap_xy = false,
    .init = vendor_init,
    .init_len = sizeof(vendor_init) / sizeof(vendor_init[0]),
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
  // The controller's X axis runs along the panel's long side. Both axes run
  // opposite to the original R (seen in issue #1: a tap on Vol+ hit Chrome);
  // the on-screen calibration corrects whatever is left per unit.
  return touch_map({DISP_W, DISP_H, false, false, true}, ry * DISP_W / 4096, rx * DISP_H / 4096, x, y);
}
