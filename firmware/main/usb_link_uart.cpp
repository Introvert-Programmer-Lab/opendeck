// Link over UART0, for boards whose USB connector is wired to a USB-UART
// bridge (CH340, CP2102). The console is disabled on these boards so nothing
// else writes to the port.
#include "usb_link.h"
#include "board.h"
#include "driver/uart.h"
#include "esp_system.h"
#include "soc/soc_caps.h"
#if CONFIG_IDF_TARGET_ESP32S3
#include "soc/rtc_cntl_reg.h"
#endif

static const uart_port_t PORT = UART_NUM_0;

void usb_link_start(void) {
  uart_config_t cfg = {};
  cfg.baud_rate = LINK_BAUD;
  cfg.data_bits = UART_DATA_8_BITS;
  cfg.parity = UART_PARITY_DISABLE;
  cfg.stop_bits = UART_STOP_BITS_1;
  cfg.flow_ctrl = UART_HW_FLOWCTRL_DISABLE;
  cfg.source_clk = UART_SCLK_DEFAULT;
  uart_driver_install(PORT, 16384, 8192, 0, nullptr, 0);
  uart_param_config(PORT, &cfg);
#ifdef BOARD_VIRTUAL
  // QEMU does not emulate the receive timeout, so bytes would wait in the FIFO
  // until it fills. Too many interrupts for real hardware at this baud rate.
  uart_set_rx_full_threshold(PORT, 1);
#endif
}

size_t usb_link_read(uint8_t *buf, size_t max, uint32_t timeout_ms) {
  int n = uart_read_bytes(PORT, buf, max, pdMS_TO_TICKS(timeout_ms));
  return n > 0 ? n : 0;
}

void usb_link_write(const char *s, size_t n) { uart_write_bytes(PORT, s, n); }

bool usb_hid_ready(void) { return false; }

void usb_hid_run(const std::vector<HidOp> &) {}

bool usb_can_reboot_to_download(void) {
#if CONFIG_IDF_TARGET_ESP32S3
  return true;
#else
  // The classic ESP32 has no software entry to download mode; the app resets
  // it through the bridge's DTR and RTS lines instead.
  return false;
#endif
}

void usb_reboot_to_download(void) {
#if CONFIG_IDF_TARGET_ESP32S3
  REG_WRITE(RTC_CNTL_OPTION1_REG, RTC_CNTL_FORCE_DOWNLOAD_BOOT);
  esp_restart();
#endif
}
