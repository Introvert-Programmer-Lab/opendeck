// Sunton ESP32-2432S024C: 2.4" with capacitive touch.
// Classic ESP32 (no PSRAM, so the screen is drawn in bands), 240x320 ILI9341
// on SPI, CST820 capacitive touch, USB-UART bridge.
#include "board.h"
#include "drivers.h"

// ILI9341 power and gamma settings (the usual values for these panels).
static const LcdCmd vendor_init[] = {
    {0xCF, 3, {0x00, 0xC1, 0x30}, 0},
    {0xED, 4, {0x64, 0x03, 0x12, 0x81}, 0},
    {0xE8, 3, {0x85, 0x00, 0x78}, 0},
    {0xCB, 5, {0x39, 0x2C, 0x00, 0x34, 0x02}, 0},
    {0xF7, 1, {0x20}, 0},
    {0xEA, 2, {0x00, 0x00}, 0},
    {0xC0, 1, {0x10}, 0},
    {0xC1, 1, {0x00}, 0},
    {0xC5, 2, {0x30, 0x30}, 0},
    {0xC7, 1, {0xB7}, 0},
    {0xB1, 2, {0x00, 0x1A}, 0},
    {0xB6, 3, {0x08, 0x82, 0x27}, 0},
    {0xF2, 1, {0x00}, 0},
    {0x26, 1, {0x01}, 0},
    {0xE0, 15, {0x0F, 0x2A, 0x28, 0x08, 0x0E, 0x08, 0x54, 0xA9, 0x43, 0x0A, 0x0F, 0x00, 0x00, 0x00, 0x00}, 0},
    {0xE1, 15, {0x00, 0x15, 0x17, 0x07, 0x11, 0x06, 0x2B, 0x56, 0x3C, 0x05, 0x10, 0x0F, 0x3F, 0x3F, 0x0F}, 0},
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

static i2c_master_bus_handle_t bus;

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
  bus = i2c_bus_init(GPIO_NUM_33, GPIO_NUM_32, true);
  cst816_init(bus, GPIO_NUM_25);
}

bool board_touch_read(int16_t *x, int16_t *y) {
  int rx, ry;
  if (!cst816_read(&rx, &ry)) return false;
  return touch_map({DISP_W, DISP_H, false, false, false}, rx, ry, x, y);
}
