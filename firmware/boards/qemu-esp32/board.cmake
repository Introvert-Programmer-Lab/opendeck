# Virtual board for Espressif's QEMU: no display or touch hardware. The screen
# is a hash of every pixel drawn, printed on the console for tools/qemu_test.py.
set(BOARD_TARGET esp32)
set(BOARD_FLASH 4mb)
set(BOARD_PSRAM none)
set(BOARD_LINK uart)
set(BOARD_DRIVERS)
set(BOARD_DECK 240x320)
