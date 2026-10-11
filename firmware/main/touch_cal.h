// Touch calibration for resistive panels. Every unit of these cheap boards is
// a little different (some batches even have the touch film mounted mirrored),
// so the board's fixed mapping is corrected with an affine transform measured
// by tapping three targets. Stored in NVS, identity until calibrated.
#pragma once
#include <stdint.h>

struct TouchCal {
  float a, b, c;  // x' = a*x + b*y + c
  float d, e, f;  // y' = d*x + e*y + f
};

// The three on-screen targets, in native panel coordinates.
void touch_cal_targets(int w, int h, int tx[3], int ty[3]);
// Solve the transform that maps the measured points onto the targets.
// False if the points are (nearly) collinear or too close together.
bool touch_cal_solve(const int mx[3], const int my[3], const int tx[3], const int ty[3], TouchCal *out);

bool touch_cal_load(void);  // true if a stored calibration was found
void touch_cal_save(const TouchCal &cal);
void touch_cal_clear(void);
void touch_cal_set(const TouchCal &cal);
bool touch_cal_active(void);
// Apply the current calibration in place; false if the point lands off screen.
bool touch_cal_apply(int16_t *x, int16_t *y, int w, int h);
