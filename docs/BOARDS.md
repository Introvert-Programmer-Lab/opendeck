# Boards

OpenDeck has firmware for the eleven most common families of cheap ESP32 touch
screens, seventeen models in all. Between them they cover most of what
AliExpress, Amazon and Temu sell as "ESP32 display", "smart display" or
"Cheap Yellow Display".

You do not need to know which one you have. Press **Install firmware** in the
app and it finds out on its own: it reads the chip, the USB connection and the
flash size, then checks where the touch controller and display answer. It only
installs when that matches one of the boards below. If it does not, the app
says the board is not supported and writes nothing to it.

When two models look identical to the app (the 4.3", 5" and 7" 800x480 boards
use the same chip and touch controller), it asks you to pick the one printed on
the back of the board.

Installing needs the Windows app for now. The Android app is paused until its
USB serial library builds with the current Android tools.

## Supported boards

| # | Family | Models | Screen | Chip | Status |
|---|---|---|---|---|---|
| 1 | 3.5" Guition | **JC3248W535C** | 320x480 IPS, capacitive | ESP32-S3, 16 MB, native USB | tested |
| 2 | 2.8" Cheap Yellow Display | **ESP32-2432S028R**, ESP32-2432S028R v3 (USB-C, ST7789) | 240x320, resistive | ESP32, 4 MB | from pinout |
| 3 | 2.8" capacitive CYD | **JC2432W328C** | 240x320 IPS, capacitive | ESP32, 4 MB | from pinout |
| 4 | 2.4" CYD | **ESP32-2432S024C**, ESP32-2432S024R | 240x320, capacitive or resistive | ESP32, 4 MB | from pinout |
| 5 | 3.2" CYD | **ESP32-2432S032C** | 240x320 IPS, capacitive | ESP32, 4 MB | from pinout |
| 6 | 3.5" ESP32 | **ESP32-3248S035C**, ESP32-3248S035R | 320x480, capacitive or resistive | ESP32, 4 MB | from pinout |
| 7 | 4.3" 480x272 | **JC4827W543C**, ESP32-4827S043C | 480x272, capacitive | ESP32-S3 | from pinout |
| 8 | 4.3" and 5" 800x480 | **ESP32-8048S043C**, ESP32-8048S050C, JC8048W550C | 800x480 IPS, capacitive | ESP32-S3, 16 MB | from pinout |
| 9 | 7" 800x480 | **ESP32-8048S070C** | 800x480, capacitive | ESP32-S3, 16 MB | from pinout |
| 10 | 4" square | **ESP32-4848S040C** | 480x480 IPS, capacitive | ESP32-S3, 16 MB | from pinout |
| 11 | 2.8" ESP32-S3 | **ES3C28P** (sold by Hosyond) | 240x320 IPS, capacitive | ESP32-S3, 16 MB, native USB | from pinout |

**Tested** means run on real hardware. **From pinout** means the firmware is
built from the board's published schematic and the configurations other open
source projects use for it, but nobody has reported back yet. If you try one,
please open an issue and say how it went. If colors look like a photo
negative, turn on **Invert colors** in the app's deck settings.

### Native USB and USB-UART boards

Only the JC3248W535, JC4827W543 and ES3C28P connect the ESP32-S3's own USB to the
USB-C port. Those two also act as a USB keyboard, so shortcuts, typing and
media keys work with no app running.

All the other boards reach the chip through a USB-UART bridge (CH340 or
CP2102). They work the same way with the app open, over the cable or over
Wi-Fi, but cannot act as a keyboard by themselves. On Windows the CH340
driver installs on its own through Windows Update; if the board does not
show up, install it from the chip maker (WCH).

## Where to buy

Listings change often. The links below were checked when they were added: right board, in stock.

**Before you order, check the letter after the model number.** `C` is
capacitive touch, `R` is resistive, `N` has no touch. OpenDeck needs a touch
screen, so avoid `N`.

| Board | Temu | Amazon | Newegg |
|---|---|---|---|
| JC3248W535C | | [DIYmalls](https://www.amazon.com/dp/B0DGXRZ58V) | |
| ESP32-2432S028R | [2 pack](https://www.temu.com/2-sets-of-esp32-development-boards-with-2-8-inch-240-320-resolution-lcd-display-tft-module-with--semiconductor-product-circuit-board-prototype-g-606476089325517.html) | [AITRIP](https://www.amazon.com/dp/B0CKYVPWX9), [AITRIP 2 pack](https://www.amazon.com/dp/B0CLR7MQ91), [DIYmalls with case](https://www.amazon.com/dp/B0D8W9DSYZ) | |
| ES3C28P | | [Hosyond](https://www.amazon.com/dp/B0FKG7WRWV) | |
| JC2432W328C | | [DIYmalls](https://www.amazon.com/dp/B0D5H84RDB), [with case](https://www.amazon.com/dp/B0FF1XFSCV) | [DIYmalls](https://www.newegg.com/p/3C6-00V6-00SX1) |
| ESP32-2432S024C | | [DIYmalls](https://www.amazon.com/dp/B0CLGD2DG6), [AITRIP 2 pack](https://www.amazon.com/dp/B0DC6DV88F) | [DIYmalls](https://www.newegg.com/p/3C6-03VM-015U2) |
| ESP32-2432S032C | | [DIYmalls](https://www.amazon.com/dp/B0CLGDHS16) | [DIYmalls](https://www.newegg.com/p/3C6-004T-000F2) |
| ESP32-3248S035C | | [DIYmalls](https://www.amazon.com/dp/B0C4KSKW96), [with case](https://www.amazon.com/dp/B0F42LTCRQ) | |
| ESP32-8048S043C | | [DIYmalls](https://www.amazon.com/dp/B0CLGCMWQ7) | |
| ESP32-8048S050C | | [DIYmalls](https://www.amazon.com/dp/B0DRYS8ZTW) | |

The JC4827W543C, ESP32-4827S043C, ESP32-8048S070C and ESP32-4848S040C are
mostly sold on Temu and AliExpress. Search for the model number and check the
listing photos: the model is printed on the back of the board. Temu titles
rarely include it, so the photo is the reliable way to tell. If the app does
not recognise the board, it says so and writes nothing.

You also need a USB-C cable that carries data. Some cables only charge.

## How the app recognises a board

Detection runs while the board sits in the ESP32's ROM bootloader, before
anything is erased:

1. The chip ID says ESP32 or ESP32-S3. Anything else is refused.
2. The USB IDs say whether the port is the chip's own USB or a CH340/CP2102
   bridge, and the flash chip reports its size.
3. Only boards with that chip, connection and flash stay on the list. For each,
   the app drives the touch controller's pins and checks for an answer: a GT911
   at 0x5D or 0x14 (whose configured resolution tells 800x480 from 480x272), a
   CST816 or CST820 at 0x15, an FT6336G at 0x38, the JC3248W535's controller at 0x3B, or an XPT2046
   on one of the two SPI buses the resistive boards use.
4. If boards with different display chips are still left, it reads the display
   controller's ID (ILI9341, ST7789 or ST7796).

These are read-only checks for the parts on the board. A board is only
accepted when its own touch controller answered. Right before writing, the
flasher checks again that the firmware image was built for the chip that is
plugged in and that the flash is big enough.

If you are sure about your board and detection disagrees (for example a
sleeping touch controller that did not answer), the app lets you pick from the
boards that share its chip, connection and flash, after a warning.

## Adding a board

Each board is a folder in `firmware/boards/`:

- `board.cmake`: the chip (`BOARD_TARGET`), flash size, PSRAM, USB link, the
  shared drivers it uses from `firmware/main/drivers/`, and the default deck
  size.
- `board_config.h`: screen size and name.
- `board.cpp`: pins and init for the display, touch and backlight, filling in
  the functions declared in `firmware/main/board.h`.

Build it with `idf.py -B build/<id> -DOPENDECK_BOARD=<id> build`, add it to the
build matrix in `.github/workflows/`, and add a `BoardProfile` to
`lib/core/services/flasher/boards.dart` with the pins detection should check.
`test/board_detect_test.dart` fails if the app's entry and the firmware folder
disagree. Pull requests that add boards are welcome.

## Factory firmware

The JC3248W535 ships with a Guition demo program. To put it back, open the
app, go to **Settings > Set up a board > Set up a new board** and press
**Restore factory firmware**.

The app downloads Guition's image (`JC3248W535C_I_Y.bin` from the
JC3248W535EN data package, an Arduino build from July 2024), checks its
SHA-256 against the one pinned in the app
(`41a39a2fef1a2af92b9d9b42984402445267b4b61a2f4288e7ff428140a14d79`) and writes
it from address `0x0`. The image belongs to Guition and is not covered by
OpenDeck's license. To restore without the app:

```
python -m esptool --chip esp32s3 write_flash 0x0 JC3248W535C_I_Y.bin
```

The other boards ship with demo programs that are not published as full
images, so the app has nothing to restore for them. You can install OpenDeck
again at any time.
