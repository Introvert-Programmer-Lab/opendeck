// JPEG drawing through the TJpgDec decoder in the chip's ROM. Images stream
// from flash block by block, so no full-size buffer is needed, and decoding
// stops as soon as the canvas is filled.
#pragma once
#include <stdint.h>
#include <stddef.h>
#include "gfx.h"

// Draw the image with its top-left corner at (x, y), clipped to the canvas.
bool jpeg_draw_file(const Canvas &c, const char *path, int x, int y);
bool jpeg_draw_mem(const Canvas &c, const uint8_t *data, size_t len, int x, int y);
