// USB: one composite device = CDC serial (app link) + HID (keyboard + media keys).
// HID lets the deck send shortcuts, media keys and typed text on its own, with
// no app running on the computer.
#include "usb_link.h"
#include <string.h>
#include "tinyusb.h"
#include "tusb_cdc_acm.h"
#include "class/hid/hid_device.h"
#include "freertos/FreeRTOS.h"
#include "freertos/stream_buffer.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "esp_system.h"
#include "esp_mac.h"
#include "soc/rtc_cntl_reg.h"

#define RID_KEYBOARD 1
#define RID_CONSUMER 2

enum { ITF_CDC = 0, ITF_CDC_DATA, ITF_HID, ITF_TOTAL };
#define CONFIG_TOTAL_LEN (TUD_CONFIG_DESC_LEN + TUD_CDC_DESC_LEN + TUD_HID_DESC_LEN)

static const uint8_t hid_report[] = {
    TUD_HID_REPORT_DESC_KEYBOARD(HID_REPORT_ID(RID_KEYBOARD)),
    TUD_HID_REPORT_DESC_CONSUMER(HID_REPORT_ID(RID_CONSUMER)),
};

static const uint8_t config_desc[] = {
    TUD_CONFIG_DESCRIPTOR(1, ITF_TOTAL, 0, CONFIG_TOTAL_LEN, 0, 200),
    TUD_CDC_DESCRIPTOR(ITF_CDC, 4, 0x81, 8, 0x02, 0x82, 64),
    TUD_HID_DESCRIPTOR(ITF_HID, 5, HID_ITF_PROTOCOL_NONE, sizeof(hid_report), 0x83, 16, 5),
};

static const tusb_desc_device_t device_desc = {
    .bLength = sizeof(tusb_desc_device_t),
    .bDescriptorType = TUSB_DESC_DEVICE,
    .bcdUSB = 0x0200,
    .bDeviceClass = TUSB_CLASS_MISC,  // IAD: required for CDC in a composite device
    .bDeviceSubClass = MISC_SUBCLASS_COMMON,
    .bDeviceProtocol = MISC_PROTOCOL_IAD,
    .bMaxPacketSize0 = CFG_TUD_ENDPOINT0_SIZE,
    .idVendor = 0x303A,  // Espressif
    .idProduct = 0x4004,
    .bcdDevice = 0x0100,
    .iManufacturer = 1,
    .iProduct = 2,
    .iSerialNumber = 3,
    .bNumConfigurations = 1,
};

static char serial_str[16];
static const char *strings[] = {
    (const char[]){0x09, 0x04},
    "OpenDeck",
    "OpenDeck",
    serial_str,
    "OpenDeck link",
    "OpenDeck keys",
};

static StreamBufferHandle_t rx_stream;

extern "C" uint8_t const *tud_hid_descriptor_report_cb(uint8_t) { return hid_report; }
extern "C" uint16_t tud_hid_get_report_cb(uint8_t, uint8_t, hid_report_type_t, uint8_t *, uint16_t) { return 0; }
extern "C" void tud_hid_set_report_cb(uint8_t, uint8_t, hid_report_type_t, uint8_t const *, uint16_t) {}

static void on_rx(int itf, cdcacm_event_t *) {
  static uint8_t buf[CONFIG_TINYUSB_CDC_RX_BUFSIZE];
  size_t n = 0;
  if (tinyusb_cdcacm_read((tinyusb_cdcacm_itf_t)itf, buf, sizeof(buf), &n) == ESP_OK && n)
    xStreamBufferSend(rx_stream, buf, n, pdMS_TO_TICKS(200));
}

static void on_line_coding(int, cdcacm_event_t *e) {
  // Arduino-style "1200 baud touch": reboot into the ROM bootloader for flashing.
  if (e->line_coding_changed_data.p_line_coding->bit_rate == 1200) usb_reboot_to_download();
}

bool usb_can_reboot_to_download(void) { return true; }

void usb_reboot_to_download(void) {
  // Hand the USB PHY back to USB-Serial/JTAG (these RTC bits survive a restart),
  // then restart into download mode so esptool can flash over the same cable.
  CLEAR_PERI_REG_MASK(RTC_CNTL_USB_CONF_REG, RTC_CNTL_SW_HW_USB_PHY_SEL | RTC_CNTL_SW_USB_PHY_SEL | RTC_CNTL_USB_PAD_ENABLE);
  REG_WRITE(RTC_CNTL_OPTION1_REG, RTC_CNTL_FORCE_DOWNLOAD_BOOT);
  esp_restart();
}

void usb_link_start(void) {
  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_WIFI_STA);
  snprintf(serial_str, sizeof(serial_str), "%02X%02X%02X%02X%02X%02X", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  rx_stream = xStreamBufferCreate(16384, 1);

  tinyusb_config_t cfg = {};
  cfg.device_descriptor = &device_desc;
  cfg.string_descriptor = strings;
  cfg.string_descriptor_count = sizeof(strings) / sizeof(strings[0]);
  cfg.external_phy = false;
  cfg.configuration_descriptor = config_desc;
  ESP_ERROR_CHECK(tinyusb_driver_install(&cfg));

  tinyusb_config_cdcacm_t acm = {};
  acm.usb_dev = TINYUSB_USBDEV_0;
  acm.cdc_port = TINYUSB_CDC_ACM_0;
  acm.callback_rx = on_rx;
  acm.callback_line_coding_changed = on_line_coding;
  ESP_ERROR_CHECK(tusb_cdc_acm_init(&acm));
}

size_t usb_link_read(uint8_t *buf, size_t max, uint32_t timeout_ms) {
  return xStreamBufferReceive(rx_stream, buf, max, pdMS_TO_TICKS(timeout_ms));
}

void usb_link_write(const char *s, size_t n) {
  if (!tud_mounted()) return;
  while (n) {
    size_t w = tinyusb_cdcacm_write_queue(TINYUSB_CDC_ACM_0, (const uint8_t *)s, n);
    tinyusb_cdcacm_write_flush(TINYUSB_CDC_ACM_0, pdMS_TO_TICKS(30));
    if (w == 0) return;  // nobody reading
    s += w;
    n -= w;
  }
}

bool usb_hid_ready(void) { return tud_mounted() && tud_hid_ready(); }

// HID macros
// US-layout ASCII -> (keycode, needs shift)
static bool ascii_to_key(char c, uint8_t *kc, bool *shift) {
  static const char *shifted_syms = "!@#$%^&*()";
  static const char *row = "1234567890";
  *shift = false;
  if (c >= 'a' && c <= 'z') { *kc = HID_KEY_A + (c - 'a'); return true; }
  if (c >= 'A' && c <= 'Z') { *kc = HID_KEY_A + (c - 'A'); *shift = true; return true; }
  if (c >= '1' && c <= '9') { *kc = HID_KEY_1 + (c - '1'); return true; }
  if (c == '0') { *kc = HID_KEY_0; return true; }
  const char *p = strchr(shifted_syms, c);
  if (p && c) { *kc = HID_KEY_1 + (row[p - shifted_syms] == '0' ? 9 : row[p - shifted_syms] - '1'); *shift = true; return true; }
  struct M { char c; uint8_t k; bool s; };
  static const M map[] = {
      {' ', HID_KEY_SPACE, false}, {'\n', HID_KEY_ENTER, false}, {'\t', HID_KEY_TAB, false},
      {'-', HID_KEY_MINUS, false}, {'_', HID_KEY_MINUS, true}, {'=', HID_KEY_EQUAL, false}, {'+', HID_KEY_EQUAL, true},
      {'[', HID_KEY_BRACKET_LEFT, false}, {'{', HID_KEY_BRACKET_LEFT, true}, {']', HID_KEY_BRACKET_RIGHT, false},
      {'}', HID_KEY_BRACKET_RIGHT, true}, {'\\', HID_KEY_BACKSLASH, false}, {'|', HID_KEY_BACKSLASH, true},
      {';', HID_KEY_SEMICOLON, false}, {':', HID_KEY_SEMICOLON, true}, {'\'', HID_KEY_APOSTROPHE, false},
      {'"', HID_KEY_APOSTROPHE, true}, {'`', HID_KEY_GRAVE, false}, {'~', HID_KEY_GRAVE, true},
      {',', HID_KEY_COMMA, false}, {'<', HID_KEY_COMMA, true}, {'.', HID_KEY_PERIOD, false}, {'>', HID_KEY_PERIOD, true},
      {'/', HID_KEY_SLASH, false}, {'?', HID_KEY_SLASH, true},
  };
  for (auto &m : map)
    if (m.c == c) { *kc = m.k; *shift = m.s; return true; }
  return false;
}

static void wait_ready(void) {
  for (int i = 0; i < 50 && !tud_hid_ready(); i++) vTaskDelay(pdMS_TO_TICKS(2));
}

static void key_tap(uint8_t mods, const uint8_t *keys, int nkeys) {
  uint8_t kc[6] = {0};
  for (int i = 0; i < nkeys && i < 6; i++) kc[i] = keys[i];
  wait_ready();
  tud_hid_keyboard_report(RID_KEYBOARD, mods, kc);
  vTaskDelay(pdMS_TO_TICKS(20));
  wait_ready();
  tud_hid_keyboard_report(RID_KEYBOARD, 0, NULL);
  vTaskDelay(pdMS_TO_TICKS(12));
}

static void consumer_tap(uint16_t usage) {
  wait_ready();
  tud_hid_report(RID_CONSUMER, &usage, 2);
  vTaskDelay(pdMS_TO_TICKS(20));
  uint16_t none = 0;
  wait_ready();
  tud_hid_report(RID_CONSUMER, &none, 2);
  vTaskDelay(pdMS_TO_TICKS(10));
}

void usb_hid_run(const std::vector<HidOp> &ops) {
  for (const auto &op : ops) {
    switch (op.kind) {
      case HidOp::KEYS: key_tap(op.mods, op.keys, op.nkeys); break;
      case HidOp::CONSUMER: consumer_tap(op.usage); break;
      case HidOp::WAIT: vTaskDelay(pdMS_TO_TICKS(op.usage)); break;
      case HidOp::TEXT:
        for (char c : op.text) {
          uint8_t kc;
          bool shift;
          if (ascii_to_key(c, &kc, &shift)) key_tap(shift ? KEYBOARD_MODIFIER_LEFTSHIFT : 0, &kc, 1);
        }
        break;
    }
  }
}
