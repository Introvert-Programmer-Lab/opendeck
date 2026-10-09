// QSPI panels that use the 0x02 (command) / 0x32 (pixels) framing, such as the
// NV3041A. Commands go out on one line; pixel data on four.
#include "drivers.h"
#include "esp_lcd_panel_io.h"
#include "esp_heap_caps.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

#define ROWS 16

static esp_lcd_panel_io_handle_t io;
static SemaphoreHandle_t free_bufs;
static uint16_t *bufs[2];
static int next_buf;

static bool IRAM_ATTR on_done(esp_lcd_panel_io_handle_t, esp_lcd_panel_io_event_data_t *, void *) {
  BaseType_t woken = pdFALSE;
  xSemaphoreGiveFromISR(free_bufs, &woken);
  return woken == pdTRUE;
}

static void cmd(uint8_t c, const uint8_t *data = nullptr, size_t len = 0) {
  esp_lcd_panel_io_tx_param(io, (0x02u << 24) | (c << 8), data, len);
}

void qspi_panel_init(const QspiPanelConfig &cfg, int w, int h) {
  spi_bus_config_t bus = {};
  bus.sclk_io_num = cfg.sclk;
  bus.data0_io_num = cfg.d0;
  bus.data1_io_num = cfg.d1;
  bus.data2_io_num = cfg.d2;
  bus.data3_io_num = cfg.d3;
  bus.max_transfer_sz = w * ROWS * 2;
  spi_bus_initialize(cfg.host, &bus, SPI_DMA_CH_AUTO);

  free_bufs = xSemaphoreCreateCounting(2, 2);
  esp_lcd_panel_io_spi_config_t io_cfg = {};
  io_cfg.cs_gpio_num = cfg.cs;
  io_cfg.dc_gpio_num = GPIO_NUM_NC;
  io_cfg.spi_mode = 0;
  io_cfg.pclk_hz = cfg.pclk_hz;
  io_cfg.trans_queue_depth = 4;
  io_cfg.on_color_trans_done = on_done;
  io_cfg.lcd_cmd_bits = 32;
  io_cfg.lcd_param_bits = 8;
  io_cfg.flags.quad_mode = 1;
  esp_lcd_new_panel_io_spi((esp_lcd_spi_bus_handle_t)cfg.host, &io_cfg, &io);

  if (cfg.rst != GPIO_NUM_NC) {
    gpio_set_direction(cfg.rst, GPIO_MODE_OUTPUT);
    gpio_set_level(cfg.rst, 0);
    vTaskDelay(pdMS_TO_TICKS(20));
    gpio_set_level(cfg.rst, 1);
    vTaskDelay(pdMS_TO_TICKS(120));
  }
  for (size_t i = 0; i < cfg.init_len; i++) {
    cmd(cfg.init[i].cmd, cfg.init[i].data, cfg.init[i].len);
    if (cfg.init[i].delay_ms) vTaskDelay(pdMS_TO_TICKS(cfg.init[i].delay_ms));
  }
  for (auto &b : bufs) b = (uint16_t *)heap_caps_malloc(w * ROWS * 2, MALLOC_CAP_DMA | MALLOC_CAP_INTERNAL);
}

void qspi_panel_draw(int x, int y, int w, int h, const uint16_t *px) {
  uint8_t ca[4] = {(uint8_t)(x >> 8), (uint8_t)x, (uint8_t)((x + w - 1) >> 8), (uint8_t)(x + w - 1)};
  uint8_t ra[4] = {(uint8_t)(y >> 8), (uint8_t)y, (uint8_t)((y + h - 1) >> 8), (uint8_t)(y + h - 1)};
  cmd(0x2A, ca, 4);
  cmd(0x2B, ra, 4);
  for (int row = 0; row < h; row += ROWS) {
    int n = h - row < ROWS ? h - row : ROWS;
    xSemaphoreTake(free_bufs, portMAX_DELAY);
    uint16_t *dst = bufs[next_buf];
    next_buf ^= 1;
    const uint16_t *src = px + row * w;
    for (int i = 0; i < w * n; i++) dst[i] = __builtin_bswap16(src[i]);
    // RAMWR starts at the window origin; RAMWRC continues where the last strip ended.
    uint32_t c = (0x32u << 24) | ((row == 0 ? 0x2C : 0x3C) << 8);
    esp_lcd_panel_io_tx_color(io, c, dst, w * n * 2);
  }
  xSemaphoreTake(free_bufs, portMAX_DELAY);
  xSemaphoreTake(free_bufs, portMAX_DELAY);
  xSemaphoreGive(free_bufs);
  xSemaphoreGive(free_bufs);
}
