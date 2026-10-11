// One-pass page drawing for boards without PSRAM. A baseline JPEG can only be
// decoded from the top, so drawing the screen band by band with jpeg_draw_file
// re-decodes everything above each band (about 5x the work for a full screen).
// This decodes the page once and hands out each band as soon as it is complete.
#pragma once
#include <stdint.h>
#include "gfx.h"

// Called with each finished band, in order; draw overlays into it and send it to the panel.
typedef void (*BandFn)(const Canvas &band);

// Decode a screen-sized image from a file, top-left at (0, 0), into bands of
// band_h rows (a multiple of 16) using buf (screen_w * band_h pixels). Only bands
// that meet rows [y0, y1) reach fn, and decoding stops after y1. Rows the image
// does not cover are filled with bg. Returns false if the file can't be decoded;
// the bands of [y0, y1) are still delivered (filled with bg) so the screen stays whole.
bool jpeg_stream_file(const char *path, uint16_t *buf, int screen_w, int screen_h, int band_h, int y0, int y1, uint16_t bg,
                      BandFn fn);
