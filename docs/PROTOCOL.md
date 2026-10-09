# Deck protocol

The app and the board talk in JSON, one object per line (`\n` terminated), over
either link:

- **USB:** on boards with native USB (ESP32-S3 JC3248W535, JC4827W543), the firmware's CDC serial port (USB VID `0x303A`, PID `0x4004`); baud rate is ignored. On boards with a USB-UART bridge (CH340 `0x1A86`, CP210x `0x10C4`), UART0 at 921600 baud, 8N1. Keep DTR and RTS released: they drive the chip's reset and boot pins.
- **Wi-Fi:** TCP port `7777`. Up to 3 clients at once.

Every request has a `t` field with the command name. The board answers each
request with one line, normally `{"t":"ok"}` or `{"t":"err","m":"reason"}`.
Send one request at a time. Lines the board sends on its own (key taps, page
changes) can arrive at any time between replies. Lines can be up to 8 KB.
Parse from the first `{`, since boot log text can come before it.

Hosts send `{"t":"ping"}` about every 2 seconds. The board uses this to show
the connection dot and to decide whether a desktop app is there to run actions.

## Discovery

Send the 9 bytes `OPENDECK?` as a UDP broadcast to port `7778` (or to
`192.168.4.1` while connected to the board's setup hotspot). Every board
answers with its `hello` object (below). Boards also announce
`_opendeck._tcp` over mDNS, with the host name `opendeck`.

## Commands

| Request | Reply | What it does |
|---|---|---|
| `{"t":"hello"}` | hello object | Board info, see below. |
| `{"t":"ping"}` | `{"t":"pong"}` | Keep-alive. |
| `{"t":"host","exec":true}` | ok | `exec: true` means this host runs actions (the desktop app). Phones send `false`. |
| `{"t":"begin"}` | ok | Start a deck upload into a staging folder. |
| `{"t":"put","f":"p0.jpg","n":12345}` | ok | Open file `f` in the staging folder, `n` bytes long. Names are 1 to 31 characters of `A-Z a-z 0-9 _ - .`. |
| `{"t":"data","d":"<base64>"}` | ok | Append up to 3072 bytes to the open file. |
| `{"t":"commit"}` | ok | Replace the deck with the staging folder. Needs a `deck.json`. |
| `{"t":"get","f":"project.json","o":0}` | `{"t":"ok","n":total,"d":"<base64>"}` | Read up to 3072 bytes of a stored deck file from offset `o`. |
| `{"t":"state","id":"<key id>","on":true}` | ok | Show the key's "on" image (toggle keys). |
| `{"t":"page","n":1}` | ok | Go to page `n`. |
| `{"t":"bright","v":200}` | ok | Backlight, 0 to 255. |
| `{"t":"wifi","ssid":"...","pass":"..."}` | ok | Save Wi-Fi credentials and reconnect. |
| `{"t":"name","v":"Desk"}` | ok | Rename the board. |
| `{"t":"info","on":true}` | ok | Show or hide the connection info screen. |
| `{"t":"reset"}` | ok | Delete the deck. |
| `{"t":"reboot"}` | ok | Restart. |
| `{"t":"dfu"}` | ok | Restart into the ROM bootloader for flashing (shows up as USB-Serial/JTAG, PID `0x1001`). Boards behind a USB-UART bridge answer `err` on the plain ESP32; flashers use the DTR/RTS reset there. |
| `{"t":"lcd","v":1}` | ok | Pick the panel variant and restart. Bit 0 inverts colors on boards whose panels ship with either polarity. |
| `{"t":"fill","c":63488}` | ok | Fill the screen with an RGB565 color. For testing. |

On native USB boards, opening the port at 1200 baud also restarts the board into the bootloader.

### Hello

```json
{
  "t": "hello", "fw": "0.1.0", "board": "JC3248W535", "id": "jc3248w535", "name": "OpenDeck",
  "w": 320, "h": 480, "lcd": 0, "fs_total": 13565952, "fs_used": 270336,
  "psram_free": 7749444, "pages": 3, "page": 0, "port": 7777,
  "wifi": {"ap": false, "connected": true, "ssid": "home", "ip": "192.168.1.50"}
}
```

`id` names the firmware build (a folder in `firmware/boards/`), `w` and `h` the
panel's native size. The app lays the deck out for that size.

### Events from the board

| Event | When |
|---|---|
| `{"t":"key","p":0,"id":"<key id>","h":false}` | A key on page `p` was tapped. `h` is true when the board already handled it over USB HID because no desktop app (`exec: true`) is connected. |
| `{"t":"page","n":1}` | The page changed on the board. |

## Deck files

An upload is a folder of page images and a manifest. The app writes:

- `p<N>.jpg`: page `N`, rendered at the panel's native size and orientation (for example 320x480 portrait on the JC3248W535, 800x480 landscape on the ESP32-8048S043C).
- `p<N>_<K>a.jpg`: the "on" image of toggle key `K` on page `N`, cropped to the key.
- `project.json`: the editor project, so another copy of the app can load the deck back. Optional.
- `deck.json`: the manifest, uploaded last.

Images are baseline JPEG (4:4:4 or 4:2:0). Page images are full panel size,
`alt` images are the size of their key.

```json
{
  "v": 1,
  "rot": 0,
  "bright": 200,
  "acc": 53216,
  "dot": [304, 25],
  "start": 0,
  "pages": [
    {
      "img": "p0.jpg",
      "keys": [
        {"id": "a1", "r": [10, 64, 95, 89], "hid": [["c", 205]]},
        {"id": "a2", "r": [113, 64, 94, 89], "hid": [["k", 12, 14]], "alt": "p0_1a.jpg"},
        {"id": "a3", "r": [215, 64, 95, 89], "dev": {"nav": "next"}}
      ]
    }
  ]
}
```

| Field | Meaning |
|---|---|
| `rot` | Deck rotation in quarter turns clockwise. Images are already rotated; this only maps swipes. |
| `bright` | Backlight level after loading. |
| `acc` | Accent color (RGB565) for the press outline and the connection dot. |
| `dot` | Where to draw the connection dot, in panel pixels. Omitted when the page header is off. |
| `start` | Page shown after loading. |
| `keys[].r` | Key rectangle `[x, y, w, h]` in panel pixels. |
| `keys[].alt` | Image drawn over the key while its state is on. |
| `keys[].dev` | Runs on the board: `{"nav": "next"}`, `{"nav": "prev"}`, `{"nav": 2}` or `{"bright": 40}` (relative). |
| `keys[].hid` | USB HID steps the board sends itself when no desktop app handles the tap. |

HID steps:

| Step | Meaning |
|---|---|
| `["k", mods, key, ...]` | Press and release keys. `mods` is a bit mask: 1 ctrl, 2 shift, 4 alt, 8 GUI. Keys are HID usage codes. |
| `["c", usage]` | Consumer control (media) key, e.g. `205` play/pause, `233` volume up. |
| `["w", ms]` | Wait. |
| `["t", "text"]` | Type ASCII text with a US layout. |
