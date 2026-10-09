// Sunton ESP32-4827S043C: ESP32-S3, 4.3" 480x272 RGB panel, GT911 touch,
// CH340 USB-UART bridge. Built for 4 MB of flash, which also runs on 16 MB units.
#include "board.h"
#include "drivers.h"

static const RgbPanelConfig panel = {
    .pclk = GPIO_NUM_42, .hsync = GPIO_NUM_39, .vsync = GPIO_NUM_41, .de = GPIO_NUM_40,
    // B0..B4, G0..G5, R0..R4
    .data = {GPIO_NUM_45, GPIO_NUM_48, GPIO_NUM_47, GPIO_NUM_21, GPIO_NUM_14,
             GPIO_NUM_5, GPIO_NUM_6, GPIO_NUM_7, GPIO_NUM_15, GPIO_NUM_16, GPIO_NUM_4,
             GPIO_NUM_8, GPIO_NUM_3, GPIO_NUM_46, GPIO_NUM_9, GPIO_NUM_1},
    .pclk_hz = 8000000,
    .hsync_pulse = 4, .hsync_back = 43, .hsync_front = 8,
    .vsync_pulse = 4, .vsync_back = 12, .vsync_front = 8,
    .hsync_idle_low = true, .vsync_idle_low = true, .pclk_active_neg = true,
};

void board_display_init(int) {
  backlight_init(GPIO_NUM_2);
  rgb_panel_init(panel, DISP_W, DISP_H);
}

static i2c_master_bus_handle_t bus;

void board_backlight(uint8_t level) { backlight_set(level); }

void board_touch_init(void) {
  bus = i2c_bus_init(GPIO_NUM_19, GPIO_NUM_20, false);
  gt911_init(bus, GPIO_NUM_38, GPIO_NUM_18);
}

bool board_touch_read(int16_t *x, int16_t *y) {
  int rx, ry;
  if (!gt911_read(&rx, &ry)) return false;
  return touch_map({DISP_W, DISP_H, false, false, false}, rx, ry, x, y);
}

void board_display_draw(int x, int y, int w, int h, const uint16_t *px) {
  rgb_panel_draw(x, y, w, h, px);
  g_frames = g_frames + 1;
}
