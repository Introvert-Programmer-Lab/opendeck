// Sunton ESP32-3248S035R: 3.5" with resistive touch.
// Classic ESP32 (no PSRAM, so the screen is drawn in bands), 320x480 ST7796
// on SPI, XPT2046 resistive touch sharing the display bus, USB-UART bridge.
#include "board.h"
#include "drivers.h"

// ST7796 settings (command set unlock, timing, power and gamma).
static const LcdCmd vendor_init[] = {
    {0xF0, 1, {0xC3}, 0},
    {0xF0, 1, {0x96}, 0},
    {0xB4, 1, {0x01}, 0},
    {0xB6, 3, {0x80, 0x02, 0x3B}, 0},
    {0xE8, 8, {0x40, 0x8A, 0x00, 0x00, 0x29, 0x19, 0xA5, 0x33}, 0},
    {0xC1, 1, {0x06}, 0},
    {0xC2, 1, {0xA7}, 0},
    {0xC5, 1, {0x18}, 0},
    {0xE0, 14, {0xF0, 0x09, 0x0B, 0x06, 0x04, 0x15, 0x2F, 0x54, 0x42, 0x3C, 0x17, 0x14, 0x18, 0x1B}, 0},
    {0xE1, 14, {0xE0, 0x09, 0x0B, 0x06, 0x04, 0x03, 0x2B, 0x43, 0x42, 0x3B, 0x16, 0x14, 0x17, 0x1B}, 0},
    {0xF0, 1, {0x3C}, 0},
    {0xF0, 1, {0x69}, 0},
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
    .host = SPI2_HOST,
    .own_bus = false,
    .sclk = GPIO_NUM_14, .mosi = GPIO_NUM_13, .miso = GPIO_NUM_12, .cs = GPIO_NUM_33,
    .raw_min_x = 200, .raw_max_x = 3700, .raw_min_y = 240, .raw_max_y = 3800,
};

void board_display_init(int variant) {
  backlight_init(GPIO_NUM_27);
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
