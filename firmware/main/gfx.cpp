#include "gfx.h"
#include <string.h>

static inline int clampi(int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); }

// Intersect (x, y, w, h) with the canvas; false when nothing is left.
static bool clip(const Canvas &c, int x, int y, int w, int h, int &x0, int &y0, int &x1, int &y1) {
  x0 = clampi(x, c.x, c.x + c.w);
  x1 = clampi(x + w, c.x, c.x + c.w);
  y0 = clampi(y, c.y, c.y + c.h);
  y1 = clampi(y + h, c.y, c.y + c.h);
  return x1 > x0 && y1 > y0;
}

static inline uint16_t *at(const Canvas &c, int x, int y) { return c.px + (y - c.y) * c.w + (x - c.x); }

void gfx_fill(const Canvas &c, uint16_t col) {
  for (int i = 0; i < c.w * c.h; i++) c.px[i] = col;
}

void gfx_fill_rect(const Canvas &c, int x, int y, int w, int h, uint16_t col) {
  int x0, y0, x1, y1;
  if (!clip(c, x, y, w, h, x0, y0, x1, y1)) return;
  for (int yy = y0; yy < y1; yy++) {
    uint16_t *p = at(c, x0, yy);
    for (int xx = x0; xx < x1; xx++) *p++ = col;
  }
}

void gfx_darken_rect(const Canvas &c, int x, int y, int w, int h) {
  int x0, y0, x1, y1;
  if (!clip(c, x, y, w, h, x0, y0, x1, y1)) return;
  for (int yy = y0; yy < y1; yy++) {
    uint16_t *p = at(c, x0, yy);
    for (int xx = x0; xx < x1; xx++, p++) *p = (*p >> 1) & 0x7BEF;
  }
}

// Pixel is inside a rounded rect (x, y, w, h, radius r)?
static inline bool in_rrect(int px, int py, int x, int y, int w, int h, int r) {
  if (px < x || py < y || px >= x + w || py >= y + h) return false;
  int cx = px < x + r ? x + r : (px >= x + w - r ? x + w - r - 1 : px);
  int cy = py < y + r ? y + r : (py >= y + h - r ? y + h - r - 1 : py);
  int dx = px - cx, dy = py - cy;
  return dx * dx + dy * dy <= r * r;
}

void gfx_round_outline(const Canvas &c, int x, int y, int w, int h, int r, int t, uint16_t col) {
  int x0, y0, x1, y1;
  if (!clip(c, x, y, w, h, x0, y0, x1, y1)) return;
  for (int yy = y0; yy < y1; yy++) {
    bool edge_row = yy < y + r + t || yy >= y + h - r - t;
    for (int xx = x0; xx < x1; xx++) {
      if (!edge_row && xx >= x + t && xx < x + w - t) {
        xx = x + w - t - 1;
        continue;
      }
      if (in_rrect(xx, yy, x, y, w, h, r) && !in_rrect(xx, yy, x + t, y + t, w - 2 * t, h - 2 * t, r > t ? r - t : 0))
        *at(c, xx, yy) = col;
    }
  }
}

void gfx_fill_circle(const Canvas &c, int cx, int cy, int r, uint16_t col) {
  int x0, y0, x1, y1;
  if (!clip(c, cx - r, cy - r, 2 * r + 1, 2 * r + 1, x0, y0, x1, y1)) return;
  for (int yy = y0; yy < y1; yy++)
    for (int xx = x0; xx < x1; xx++) {
      int dx = xx - cx, dy = yy - cy;
      if (dx * dx + dy * dy <= r * r) *at(c, xx, yy) = col;
    }
}

void gfx_blit_screen(const Canvas &c, const uint16_t *src, int src_w) {
  for (int row = 0; row < c.h; row++) memcpy(c.px + row * c.w, src + (c.y + row) * src_w + c.x, c.w * 2);
}

static inline uint16_t blend(uint16_t bg, uint16_t fg, int a /*0..15*/) {
  int br = bg >> 11, bgg = (bg >> 5) & 0x3F, bb = bg & 0x1F;
  int fr = fg >> 11, fgg = (fg >> 5) & 0x3F, fbb = fg & 0x1F;
  int r = br + (fr - br) * a / 15, g = bgg + (fgg - bgg) * a / 15, b = bb + (fbb - bb) * a / 15;
  return (uint16_t)((r << 11) | (g << 5) | b);
}

int gfx_text_width(const font_t &f, const char *s) {
  int w = 0;
  for (; *s; s++) {
    unsigned ch = (unsigned char)*s;
    if (ch < 32 || ch > 126) ch = '?';
    w += f.glyphs[ch - 32].adv;
  }
  return w;
}

void gfx_text(const Canvas &c, const font_t &f, int x, int y, const char *s, uint16_t col) {
  // y is the top of the line box
  if (y >= c.y + c.h || y + f.line_h <= c.y) return;
  for (; *s; s++) {
    unsigned ch = (unsigned char)*s;
    if (ch < 32 || ch > 126) ch = '?';
    const font_glyph_t &g = f.glyphs[ch - 32];
    const uint8_t *bits = f.bits + g.off;
    int stride = (g.w + 1) / 2;
    for (int gy = 0; gy < g.h; gy++) {
      int py = y + g.y + gy;
      if (py < c.y || py >= c.y + c.h) continue;
      for (int gx = 0; gx < g.w; gx++) {
        int px = x + g.x + gx;
        if (px < c.x || px >= c.x + c.w) continue;
        uint8_t b = bits[gy * stride + gx / 2];
        int a = (gx & 1) ? (b & 0x0F) : (b >> 4);
        if (a) {
          uint16_t *p = at(c, px, py);
          *p = blend(*p, col, a);
        }
      }
    }
    x += g.adv;
  }
}

void gfx_text_center(const Canvas &c, const font_t &f, int screen_w, int y, const char *s, uint16_t col) {
  gfx_text(c, f, (screen_w - gfx_text_width(f, s)) / 2, y, s, col);
}
