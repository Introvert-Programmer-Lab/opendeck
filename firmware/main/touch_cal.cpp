#include "touch_cal.h"
#include <math.h>
#include "nvs.h"

static TouchCal cal = {1, 0, 0, 0, 1, 0};
static bool active = false;
static const uint32_t MAGIC = 0x54434131;  // "TCA1"

struct Stored {
  uint32_t magic;
  TouchCal cal;
};

void touch_cal_targets(int w, int h, int tx[3], int ty[3]) {
  // Spread out and not on a line, away from the edges where resistive films are least accurate.
  tx[0] = w * 15 / 100; ty[0] = h * 12 / 100;
  tx[1] = w * 85 / 100; ty[1] = h * 45 / 100;
  tx[2] = w * 35 / 100; ty[2] = h * 88 / 100;
}

bool touch_cal_solve(const int mx[3], const int my[3], const int tx[3], const int ty[3], TouchCal *out) {
  // [mx my 1] * [a b c]^T = tx, same for y: two 3x3 systems with one matrix (Cramer's rule).
  double det = (double)mx[0] * (my[1] - my[2]) - (double)my[0] * (mx[1] - mx[2]) + ((double)mx[1] * my[2] - (double)mx[2] * my[1]);
  // The measured triangle must have a real area (the targets' one is ~25% of the screen).
  if (fabs(det) < 400.0) return false;
  auto solve = [&](const int t[3], float *p, float *q, float *r) {
    double a = (double)t[0] * (my[1] - my[2]) - (double)my[0] * (t[1] - t[2]) + ((double)t[1] * my[2] - (double)t[2] * my[1]);
    double b = (double)mx[0] * (t[1] - t[2]) - (double)t[0] * (mx[1] - mx[2]) + ((double)mx[1] * t[2] - (double)mx[2] * t[1]);
    double c = (double)mx[0] * ((double)my[1] * t[2] - (double)my[2] * t[1]) - (double)my[0] * ((double)mx[1] * t[2] - (double)mx[2] * t[1]) +
               (double)t[0] * ((double)mx[1] * my[2] - (double)mx[2] * my[1]);
    *p = a / det;
    *q = b / det;
    *r = c / det;
  };
  solve(tx, &out->a, &out->b, &out->c);
  solve(ty, &out->d, &out->e, &out->f);
  // Reject wild results (scale more than 4x off): a slipped finger, not a real panel.
  double sx = sqrt((double)out->a * out->a + (double)out->d * out->d);
  double sy = sqrt((double)out->b * out->b + (double)out->e * out->e);
  return sx > 0.25 && sx < 4 && sy > 0.25 && sy < 4;
}

bool touch_cal_load(void) {
  nvs_handle_t h;
  if (nvs_open("opendeck", NVS_READONLY, &h) != ESP_OK) return false;
  Stored s = {};
  size_t n = sizeof(s);
  bool ok = nvs_get_blob(h, "tcal", &s, &n) == ESP_OK && n == sizeof(s) && s.magic == MAGIC;
  nvs_close(h);
  if (ok) {
    cal = s.cal;
    active = true;
  }
  return ok;
}

void touch_cal_save(const TouchCal &c) {
  touch_cal_set(c);
  nvs_handle_t h;
  if (nvs_open("opendeck", NVS_READWRITE, &h) != ESP_OK) return;
  Stored s = {MAGIC, c};
  nvs_set_blob(h, "tcal", &s, sizeof(s));
  nvs_commit(h);
  nvs_close(h);
}

void touch_cal_clear(void) {
  cal = {1, 0, 0, 0, 1, 0};
  active = false;
}

void touch_cal_set(const TouchCal &c) {
  cal = c;
  active = true;
}

bool touch_cal_active(void) { return active; }

bool touch_cal_apply(int16_t *x, int16_t *y, int w, int h) {
  if (!active) return true;
  float fx = cal.a * *x + cal.b * *y + cal.c;
  float fy = cal.d * *x + cal.e * *y + cal.f;
  int ix = (int)lroundf(fx), iy = (int)lroundf(fy);
  // A little slack at the edges: resistive readings there are compressed.
  if (ix < -8 || iy < -8 || ix >= w + 8 || iy >= h + 8) return false;
  *x = ix < 0 ? 0 : (ix >= w ? w - 1 : ix);
  *y = iy < 0 ? 0 : (iy >= h ? h - 1 : iy);
  return true;
}
