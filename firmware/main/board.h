// Board abstraction. Each supported screen lives in firmware/boards/<id>/:
// board_config.h (size and capabilities), board.cpp (these functions),
// board.cmake (chip and drivers) and sdkconfig.defaults.
#pragma once
#include <stdint.h>
#include <stdbool.h>
#include "board_config.h"

// board_config.h defines:
//   DISP_W, DISP_H       native panel size in pixels
//   BOARD_NAME           shown in the hello reply and on the info screen
//   BOARD_FRAMEBUFFER    1: keep full frames in PSRAM; 0: draw in bands (no PSRAM)

// variant: which panel init sequence to use, for bring-up of new panels (0 = default).
void board_display_init(int variant);
// Copy w x h native little-endian RGB565 pixels (row stride w) to the panel at
// (x, y). Returns once px can be reused.
void board_display_draw(int x, int y, int w, int h, const uint16_t *px);
void board_backlight(uint8_t level);  // 0..255
void board_touch_init(void);
// True while a finger is down; coordinates in native panel space.
bool board_touch_read(int16_t *x, int16_t *y);
#ifdef BOARD_VIRTUAL
void board_virtual_tap(int x, int y);
// Rows of the screen copy, every board_virtual_shot_step() pixels; null when out of range.
const uint16_t *board_virtual_row(int y);
int board_virtual_shot_step(void);
#endif

// Diagnostics reported in the hello reply.
extern volatile uint32_t g_frames, g_flush_ms, g_flush_timeouts;
