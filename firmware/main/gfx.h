// Small drawing toolkit. Everything draws into a Canvas: a rectangle of the
// screen backed by an RGB565 buffer. Boards with PSRAM use one full-screen
// canvas; boards without it redraw the screen in horizontal bands.
#pragma once
#include <stdint.h>
#include <stddef.h>
#include "assets.h"

#define RGB565(r, g, b) (uint16_t)((((r) & 0xF8) << 8) | (((g) & 0xFC) << 3) | ((b) >> 3))

static const uint16_t COL_LIME = RGB565(0xCC, 0xFF, 0x00);
static const uint16_t COL_DARK = RGB565(0x0A, 0x10, 0x0E);
static const uint16_t COL_TEXT = RGB565(0xFB, 0xFF, 0xE9);
static const uint16_t COL_MUTED = RGB565(0x6B, 0x75, 0x70);

// Screen rectangle (x, y, w, h) backed by px, row stride w. Coordinates passed
// to the drawing functions are screen coordinates; drawing clips to the canvas.
struct Canvas {
  uint16_t *px;
  int x, y, w, h;
};

void gfx_fill(const Canvas &c, uint16_t col);
void gfx_fill_rect(const Canvas &c, int x, int y, int w, int h, uint16_t col);
void gfx_darken_rect(const Canvas &c, int x, int y, int w, int h);
void gfx_round_outline(const Canvas &c, int x, int y, int w, int h, int r, int thick, uint16_t col);
void gfx_fill_circle(const Canvas &c, int cx, int cy, int r, uint16_t col);
// Copy a screen-sized source image (row stride src_w) into the canvas.
void gfx_blit_screen(const Canvas &c, const uint16_t *src, int src_w);
int gfx_text_width(const font_t &f, const char *s);
void gfx_text(const Canvas &c, const font_t &f, int x, int y, const char *s, uint16_t col);
void gfx_text_center(const Canvas &c, const font_t &f, int screen_w, int y, const char *s, uint16_t col);

static inline bool gfx_overlaps(const Canvas &c, int x, int y, int w, int h) {
  return x < c.x + c.w && x + w > c.x && y < c.y + c.h && y + h > c.y;
}
