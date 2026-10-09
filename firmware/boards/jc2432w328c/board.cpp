// Guition JC2432W328C: 2.8" capacitive "Cheap Yellow Display" with USB-C.
// Classic ESP32 (no PSRAM, so the screen is drawn in bands), 240x320 ST7789
// on SPI, CST816 capacitive touch, USB-UART bridge.
#include "board.h"
#include "drivers.h"

static const SpiPanelConfig panel = {
    .host = SPI2_HOST,
    .sclk = GPIO_NUM_14, .mosi = GPIO_NUM_13, .miso = GPIO_NUM_12, .cs = GPIO_NUM_15, .dc = GPIO_NUM_2, .rst = GPIO_NUM_NC,
    .pclk_hz = 40000000,
    .spi_mode = 3,
    .bgr = false, .invert = true, .mirror_x = false, .mirror_y = false, .swap_xy = false,
    .init = nullptr,
    .init_len = 0,
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
