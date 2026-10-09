// MIPI DCS panels on SPI (ILI9341, ST7789, ST7796). Only standard commands are
// sent besides the board's own vendor list, so one driver fits all three.
#include "drivers.h"
#include "esp_lcd_panel_io.h"
#include "esp_heap_caps.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

#define ROWS 16  // rows per DMA transfer

static esp_lcd_panel_io_handle_t io;
static SemaphoreHandle_t free_bufs;
static uint16_t *bufs[2];
static int width;
static int next_buf;

static bool IRAM_ATTR on_done(esp_lcd_panel_io_handle_t, esp_lcd_panel_io_event_data_t *, void *) {
  BaseType_t woken = pdFALSE;
  xSemaphoreGiveFromISR(free_bufs, &woken);
  return woken == pdTRUE;
}

static void cmd(uint8_t c, const uint8_t *data = nullptr, size_t len = 0) { esp_lcd_panel_io_tx_param(io, c, data, len); }

void spi_panel_init(const SpiPanelConfig &cfg, int w, int h) {
  width = w;
  spi_bus_config_t bus = {};
  bus.sclk_io_num = cfg.sclk;
  bus.mosi_io_num = cfg.mosi;
  bus.miso_io_num = cfg.miso;
  bus.quadwp_io_num = -1;
  bus.quadhd_io_num = -1;
  bus.max_transfer_sz = w * ROWS * 2;
  spi_bus_initialize(cfg.host, &bus, SPI_DMA_CH_AUTO);

  free_bufs = xSemaphoreCreateCounting(2, 2);
  esp_lcd_panel_io_spi_config_t io_cfg = {};
  io_cfg.cs_gpio_num = cfg.cs;
  io_cfg.dc_gpio_num = cfg.dc;
  io_cfg.spi_mode = cfg.spi_mode;
  io_cfg.pclk_hz = cfg.pclk_hz;
  io_cfg.trans_queue_depth = 4;
  io_cfg.on_color_trans_done = on_done;
  io_cfg.lcd_cmd_bits = 8;
  io_cfg.lcd_param_bits = 8;
  esp_lcd_new_panel_io_spi((esp_lcd_spi_bus_handle_t)cfg.host, &io_cfg, &io);

  if (cfg.rst != GPIO_NUM_NC) {
    gpio_set_direction(cfg.rst, GPIO_MODE_OUTPUT);
    gpio_set_level(cfg.rst, 0);
    vTaskDelay(pdMS_TO_TICKS(20));
    gpio_set_level(cfg.rst, 1);
  } else {
    cmd(0x01);  // SWRESET
  }
  vTaskDelay(pdMS_TO_TICKS(120));
  cmd(0x11);  // SLPOUT
  vTaskDelay(pdMS_TO_TICKS(120));
  for (size_t i = 0; i < cfg.init_len; i++) {
    cmd(cfg.init[i].cmd, cfg.init[i].data, cfg.init[i].len);
    if (cfg.init[i].delay_ms) vTaskDelay(pdMS_TO_TICKS(cfg.init[i].delay_ms));
  }
  uint8_t colmod = 0x55;  // 16 bits per pixel
  cmd(0x3A, &colmod, 1);
  uint8_t madctl = (cfg.mirror_y ? 0x80 : 0) | (cfg.mirror_x ? 0x40 : 0) | (cfg.swap_xy ? 0x20 : 0) | (cfg.bgr ? 0x08 : 0);
  cmd(0x36, &madctl, 1);
  cmd(cfg.invert ? 0x21 : 0x20);
  cmd(0x29);  // DISPON

  for (auto &b : bufs) b = (uint16_t *)heap_caps_malloc(w * ROWS * 2, MALLOC_CAP_DMA | MALLOC_CAP_INTERNAL);
}

void spi_panel_draw(int x, int y, int w, int h, const uint16_t *px) {
  for (int row = 0; row < h; row += ROWS) {
    int n = h - row < ROWS ? h - row : ROWS;
    xSemaphoreTake(free_bufs, portMAX_DELAY);
    uint16_t *dst = bufs[next_buf];
    next_buf ^= 1;
    const uint16_t *src = px + row * w;
    for (int i = 0; i < w * n; i++) dst[i] = __builtin_bswap16(src[i]);  // the panel takes big-endian pixels
    uint8_t ca[4] = {(uint8_t)(x >> 8), (uint8_t)x, (uint8_t)((x + w - 1) >> 8), (uint8_t)(x + w - 1)};
    int y0 = y + row, y1 = y + row + n - 1;
    uint8_t ra[4] = {(uint8_t)(y0 >> 8), (uint8_t)y0, (uint8_t)(y1 >> 8), (uint8_t)y1};
    cmd(0x2A, ca, 4);
    cmd(0x2B, ra, 4);
    esp_lcd_panel_io_tx_color(io, 0x2C, dst, w * n * 2);
  }
  // Wait for both buffers so the caller can reuse px and the next call starts clean.
  xSemaphoreTake(free_bufs, portMAX_DELAY);
  xSemaphoreTake(free_bufs, portMAX_DELAY);
  xSemaphoreGive(free_bufs);
  xSemaphoreGive(free_bufs);
}
