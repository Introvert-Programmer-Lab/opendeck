// XPT2046 resistive touch controller on SPI. Samples are averaged and checked
// against a pressure threshold, then scaled with the board's calibration.
#include "drivers.h"

static spi_device_handle_t dev;
static Xpt2046Config conf;

static int sample(uint8_t command) {
  spi_transaction_t t = {};
  t.length = 24;
  t.flags = SPI_TRANS_USE_TXDATA | SPI_TRANS_USE_RXDATA;
  t.tx_data[0] = command;
  if (spi_device_polling_transmit(dev, &t) != ESP_OK) return -1;
  return ((t.rx_data[1] << 8) | t.rx_data[2]) >> 3;  // 12 bits
}

void xpt2046_init(const Xpt2046Config &cfg) {
  conf = cfg;
  if (cfg.own_bus) {
    spi_bus_config_t bus = {};
    bus.sclk_io_num = cfg.sclk;
    bus.mosi_io_num = cfg.mosi;
    bus.miso_io_num = cfg.miso;
    bus.quadwp_io_num = -1;
    bus.quadhd_io_num = -1;
    spi_bus_initialize(cfg.host, &bus, SPI_DMA_DISABLED);
  }
  spi_device_interface_config_t d = {};
  d.clock_speed_hz = 2000000;
  d.mode = 0;
  d.spics_io_num = cfg.cs;
  d.queue_size = 1;
  spi_bus_add_device(cfg.host, &d, &dev);
}

bool xpt2046_read(int *x, int *y) {
  if (!dev) return false;
  int z1 = sample(0xB1), z2 = sample(0xC1);
  if (z1 < 0 || z2 < 0) return false;
  int z = z1 + 4095 - z2;
  if (z < 400) return false;  // not pressed hard enough
  long sx = 0, sy = 0;
  for (int i = 0; i < 4; i++) {
    sx += sample(0xD1);
    sy += sample(0x91);
  }
  int rx = sx / 4, ry = sy / 4;
  // Scale the calibrated raw range to 0..4095; the board maps that to pixels.
  rx = (rx - conf.raw_min_x) * 4096 / (conf.raw_max_x - conf.raw_min_x);
  ry = (ry - conf.raw_min_y) * 4096 / (conf.raw_max_y - conf.raw_min_y);
  if (rx < 0) rx = 0;
  if (ry < 0) ry = 0;
  if (rx > 4095) rx = 4095;
  if (ry > 4095) ry = 4095;
  *x = rx;
  *y = ry;
  return true;
}
