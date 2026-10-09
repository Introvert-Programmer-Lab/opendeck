#include "jpeg.h"
#include <stdio.h>
#include <string.h>
#include "sdkconfig.h"
#if CONFIG_IDF_TARGET_ESP32
#include "esp32/rom/tjpgd.h"
#else
#include "esp32s3/rom/tjpgd.h"
#endif

namespace {

struct Session {
  FILE *file;
  const uint8_t *mem;
  size_t len, pos;
  const Canvas *canvas;
  int ox, oy;
};

// The decoder's tables and work area. Drawing happens under the main render
// lock, so one static pool is enough.
alignas(4) uint8_t pool[4096];

UINT input(JDEC *jd, BYTE *buf, UINT n) {
  Session *s = (Session *)jd->device;
  if (s->file) {
    if (buf) return fread(buf, 1, n, s->file);
    return fseek(s->file, n, SEEK_CUR) == 0 ? n : 0;
  }
  if (s->pos + n > s->len) n = s->len - s->pos;
  if (buf) memcpy(buf, s->mem + s->pos, n);
  s->pos += n;
  return n;
}

// Called per decoded block (RGB888). Returns 0 to stop once the block is
// below the canvas: everything after it would be clipped anyway.
UINT output(JDEC *jd, void *bitmap, JRECT *r) {
  Session *s = (Session *)jd->device;
  const Canvas &c = *s->canvas;
  int bx = s->ox + r->left, by = s->oy + r->top;
  int bw = r->right - r->left + 1, bh = r->bottom - r->top + 1;
  if (by >= c.y + c.h) return 0;
  if (by + bh <= c.y || bx >= c.x + c.w || bx + bw <= c.x) return 1;
  const uint8_t *rgb = (const uint8_t *)bitmap;
  for (int row = 0; row < bh; row++) {
    int sy = by + row;
    if (sy < c.y || sy >= c.y + c.h) continue;
    const uint8_t *src = rgb + row * bw * 3;
    uint16_t *dst = c.px + (sy - c.y) * c.w;
    for (int col = 0; col < bw; col++, src += 3) {
      int sx = bx + col;
      if (sx < c.x || sx >= c.x + c.w) continue;
      dst[sx - c.x] = (uint16_t)(((src[0] & 0xF8) << 8) | ((src[1] & 0xFC) << 3) | (src[2] >> 3));
    }
  }
  return 1;
}

bool run(Session &s) {
  JDEC jd;
  if (jd_prepare(&jd, input, pool, sizeof(pool), &s) != JDR_OK) return false;
  JRESULT r = jd_decomp(&jd, output, 0);
  return r == JDR_OK || r == JDR_INTR;
}

}  // namespace

bool jpeg_draw_file(const Canvas &c, const char *path, int x, int y) {
  FILE *f = fopen(path, "rb");
  if (!f) return false;
  Session s = {f, nullptr, 0, 0, &c, x, y};
  bool ok = run(s);
  fclose(f);
  return ok;
}

bool jpeg_draw_mem(const Canvas &c, const uint8_t *data, size_t len, int x, int y) {
  Session s = {nullptr, data, len, 0, &c, x, y};
  return run(s);
}
