// Link to the computer. Boards with native USB use TinyUSB (CDC serial plus a
// HID keyboard, usb_link_tinyusb.cpp). Boards whose USB port goes through a
// USB-UART bridge use UART0 (usb_link_uart.cpp), and have no HID.
#pragma once
#include <stdint.h>
#include <stddef.h>
#include <string>
#include <vector>

// One step of a key's HID macro (compiled by the app into deck.json "hid").
struct HidOp {
  enum Kind { KEYS, CONSUMER, WAIT, TEXT } kind;
  uint8_t mods = 0;
  uint8_t keys[6] = {0};
  int nkeys = 0;
  uint16_t usage = 0;  // consumer usage, or wait in ms
  std::string text;
};

void usb_link_start(void);
size_t usb_link_read(uint8_t *buf, size_t max, uint32_t timeout_ms);
void usb_link_write(const char *s, size_t n);
bool usb_hid_ready(void);
void usb_hid_run(const std::vector<HidOp> &ops);  // blocking; call from a worker task
// Restart into the ROM bootloader so the app can flash new firmware without
// buttons. Not every chip can do this from software.
bool usb_can_reboot_to_download(void);
void usb_reboot_to_download(void);

// Baud rate of the UART link. The app opens every port at this rate; native
// USB ignores it.
#define LINK_BAUD 921600
