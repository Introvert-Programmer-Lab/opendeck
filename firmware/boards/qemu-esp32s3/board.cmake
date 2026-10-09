# Virtual board for Espressif's QEMU, ESP32-S3. QEMU 9.0's S3 machine does not
# bring up PSRAM, so this one draws in strips like the plain ESP32 boards; the
# PSRAM framebuffer path is only covered on real hardware.
set(BOARD_TARGET esp32s3)
set(BOARD_FLASH 4mb)
set(BOARD_PSRAM none)
set(BOARD_LINK uart)
set(BOARD_DRIVERS)
set(BOARD_DECK 320x480)
