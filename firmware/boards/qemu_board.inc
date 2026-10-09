// Shared by the qemu-* boards. Each drawn row is hashed (FNV-1a over the
// RGB565 pixels); the screen hash, a hash of all row hashes, is printed on
// the console whenever it changes. Taps come from the "tap" test command.
#include "board.h"
#include <assert.h>
#include "esp_heap_caps.h"
#include <stdio.h>
#include "driver/uart.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static uint32_t row_hash[DISP_H];
// Copy of everything drawn, for the "shot" command. Without PSRAM it keeps
// every second pixel of every second row, so the copy does not starve the
// firmware of the memory a real board would have.
#if BOARD_FRAMEBUFFER
#define SHOT_STEP 1
#else
#define SHOT_STEP 2
#endif
#define SHOT_W (DISP_W / SHOT_STEP)
#define SHOT_H (DISP_H / SHOT_STEP)
static uint16_t *screen[SHOT_H];
static volatile bool changed = false;
static volatile int tap_x = -1, tap_y = -1, tap_reads = 0;

static uint32_t fnv(uint32_t h, const uint8_t *p, size_t n) {
  for (size_t i = 0; i < n; i++) h = (h ^ p[i]) * 16777619u;
  return h;
}

static void report_task(void *) {
  uint32_t last = 0;
  while (true) {
    vTaskDelay(pdMS_TO_TICKS(300));
    if (!changed) continue;
    changed = false;
    uint32_t h = fnv(2166136261u, (const uint8_t *)row_hash, sizeof(row_hash));
    if (h == last) continue;
    last = h;
    // Through the UART driver like the protocol, so whole lines never mix.
    char line[32];
    int n = snprintf(line, sizeof(line), "QEMU screen %08x\n", (unsigned)h);
    uart_write_bytes(UART_NUM_0, line, n);
  }
}

void board_display_init(int variant) {
  for (int y = 0; y < DISP_H; y++) row_hash[y] = 0;
  for (int y = 0; y < SHOT_H; y++) {
    screen[y] = (uint16_t *)heap_caps_calloc_prefer(SHOT_W, 2, 2, MALLOC_CAP_SPIRAM, MALLOC_CAP_DEFAULT);
    assert(screen[y]);
  }
  xTaskCreate(report_task, "qemu_report", 2048, nullptr, 1, nullptr);
}

void board_display_draw(int x, int y, int w, int h, const uint16_t *px) {
  // The shared code always draws whole rows.
  for (int r = 0; r < h; r++) {
    const uint16_t *src = px + r * w;
    row_hash[y + r] = fnv(2166136261u, (const uint8_t *)src, w * 2);
    if ((y + r) % SHOT_STEP) continue;
    uint16_t *row = screen[(y + r) / SHOT_STEP];
    for (int c = 0; c < w; c += SHOT_STEP) row[(x + c) / SHOT_STEP] = src[c];
  }
  changed = true;
  g_frames = g_frames + 1;
}

void board_backlight(uint8_t level) {}

void board_touch_init(void) {}

// A tap reads as pressed for a few polls, then released.
bool board_touch_read(int16_t *x, int16_t *y) {
  if (tap_x < 0) return false;
  *x = tap_x;
  *y = tap_y;
  tap_reads = tap_reads + 1;
  if (tap_reads >= 3) tap_x = -1;
  return true;
}

const uint16_t *board_virtual_row(int y) {
  return y >= 0 && y < SHOT_H ? screen[y] : nullptr;
}

int board_virtual_shot_step(void) { return SHOT_STEP; }

void board_virtual_tap(int x, int y) {
  tap_reads = 0;
  tap_y = y;
  tap_x = x;
}
