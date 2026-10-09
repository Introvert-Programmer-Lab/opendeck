// 16-bit parallel RGB panels. The ESP32-S3 LCD peripheral scans a framebuffer
// in PSRAM continuously; drawing copies into it. Bounce buffers in internal
// RAM keep the picture stable while Wi-Fi is busy with PSRAM.
#include "drivers.h"
#include "sdkconfig.h"
#if CONFIG_IDF_TARGET_ESP32S3
#include "esp_lcd_panel_rgb.h"
#include "esp_lcd_panel_ops.h"

static esp_lcd_panel_handle_t panel;

void rgb_panel_init(const RgbPanelConfig &cfg, int w, int h) {
  esp_lcd_rgb_panel_config_t p = {};
  p.clk_src = LCD_CLK_SRC_DEFAULT;
  p.timings.pclk_hz = cfg.pclk_hz;
  p.timings.h_res = w;
  p.timings.v_res = h;
  p.timings.hsync_pulse_width = cfg.hsync_pulse;
  p.timings.hsync_back_porch = cfg.hsync_back;
  p.timings.hsync_front_porch = cfg.hsync_front;
  p.timings.vsync_pulse_width = cfg.vsync_pulse;
  p.timings.vsync_back_porch = cfg.vsync_back;
  p.timings.vsync_front_porch = cfg.vsync_front;
  p.timings.flags.hsync_idle_low = cfg.hsync_idle_low;
  p.timings.flags.vsync_idle_low = cfg.vsync_idle_low;
  p.timings.flags.pclk_active_neg = cfg.pclk_active_neg;
  p.data_width = 16;
  p.bits_per_pixel = 16;
  p.num_fbs = 1;
  p.bounce_buffer_size_px = w * 10;
  p.hsync_gpio_num = cfg.hsync;
  p.vsync_gpio_num = cfg.vsync;
  p.de_gpio_num = cfg.de;
  p.pclk_gpio_num = cfg.pclk;
  p.disp_gpio_num = GPIO_NUM_NC;
  for (int i = 0; i < 16; i++) p.data_gpio_nums[i] = cfg.data[i];
  p.flags.fb_in_psram = 1;
  esp_lcd_new_rgb_panel(&p, &panel);
  esp_lcd_panel_reset(panel);
  esp_lcd_panel_init(panel);
}

void rgb_panel_draw(int x, int y, int w, int h, const uint16_t *px) {
  esp_lcd_panel_draw_bitmap(panel, x, y, x + w, y + h, px);
}
#endif
