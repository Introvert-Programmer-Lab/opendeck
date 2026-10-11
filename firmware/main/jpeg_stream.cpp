#include "jpeg_stream.h"
#include <stdio.h>
#include "sdkconfig.h"
#if CONFIG_IDF_TARGET_ESP32
#include "esp32/rom/tjpgd.h"
#else
#include "esp32s3/rom/tjpgd.h"
#endif

namespace {

struct Stream {
  FILE *file;
  Canvas band;  // the band being filled; band.y advances down the screen
  int screen_h, band_h, y0, y1;
  uint16_t bg;
  BandFn fn;
};

// The decoder's work area; drawing runs under the main render lock.
alignas(4) uint8_t pool[4096];

UINT input(JDEC *jd, BYTE *buf, UINT n) {
  Stream *s = (Stream *)jd->device;
  if (buf) return fread(buf, 1, n, s->file);
  return fseek(s->file, n, SEEK_CUR) == 0 ? n : 0;
}

void clear(Stream *s) {
  uint16_t *p = s->band.px;
  for (int i = 0, n = s->band.w * s->band.h; i < n; i++) p[i] = s->bg;
}

// Hand the current band out (if it is wanted) and move to the next one.
// Returns false once everything up to y1 has been delivered.
bool advance(Stream *s) {
  Canvas &b = s->band;
  if (b.y + b.h > s->y0 && b.y < s->y1) s->fn(b);
  b.y += s->band_h;
  if (b.y >= s->y1 || b.y >= s->screen_h) return false;
  b.h = s->screen_h - b.y < s->band_h ? s->screen_h - b.y : s->band_h;
  clear(s);
  return true;
}

// Blocks arrive left to right, one MCU row at a time, so a band is complete
// when the first block below it shows up.
UINT output(JDEC *jd, void *bitmap, JRECT *r) {
  Stream *s = (Stream *)jd->device;
  Canvas &c = s->band;
  int bx = r->left, by = r->top;
  int bw = r->right - r->left + 1, bh = r->bottom - r->top + 1;
  while (by >= c.y + c.h) {
    if (!advance(s)) return 0;  // past y1: stop decoding
  }
  const uint8_t *rgb = (const uint8_t *)bitmap;
  for (int row = 0; row < bh; row++) {
    int sy = by + row;
    if (sy < c.y || sy >= c.y + c.h) continue;
    const uint8_t *src = rgb + row * bw * 3;
    uint16_t *dst = c.px + (sy - c.y) * c.w;
    for (int col = 0; col < bw; col++, src += 3) {
      int sx = bx + col;
      if (sx < 0 || sx >= c.w) continue;
      dst[sx] = (uint16_t)(((src[0] & 0xF8) << 8) | ((src[1] & 0xFC) << 3) | (src[2] >> 3));
    }
  }
  return 1;
}

}  // namespace

bool jpeg_stream_file(const char *path, uint16_t *buf, int screen_w, int screen_h, int band_h, int y0, int y1, uint16_t bg,
                      BandFn fn) {
  if (y1 > screen_h) y1 = screen_h;
  Stream s = {nullptr, {buf, 0, 0, screen_w, band_h < screen_h ? band_h : screen_h}, screen_h, band_h, y0, y1, bg, fn};
  clear(&s);
  bool ok = false;
  s.file = fopen(path, "rb");
  if (s.file) {
    JDEC jd;
    if (jd_prepare(&jd, input, pool, sizeof(pool), &s) == JDR_OK) {
      JRESULT r = jd_decomp(&jd, output, 0);
      ok = r == JDR_OK || r == JDR_INTR;
    }
    fclose(s.file);
  }
  // Deliver what's left: the band in progress and any rows below the image.
  if (s.band.y < y1) {
    while (advance(&s)) {
    }
  }
  return ok;
}
