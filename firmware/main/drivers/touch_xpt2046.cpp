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

// Median of 5 readings of one channel. The first conversion after switching
// channels is the noisiest on these films, so it's taken and dropped; a median
// (not a mean) keeps one bad spike from moving the point.
static int median(uint8_t command) {
  int v[5];
  if (sample(command) < 0) return -1;
  for (int i = 0; i < 5; i++) {
    v[i] = sample(command);
    if (v[i] < 0) return -1;
  }
  for (int i = 1; i < 5; i++)
    for (int j = i; j > 0 && v[j - 1] > v[j]; j--) {
      int t = v[j];
      v[j] = v[j - 1];
      v[j - 1] = t;
    }
  return v[2];
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
  int rx = median(0xD1), ry = median(0x91);
  if (rx < 0 || ry < 0) return false;
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
