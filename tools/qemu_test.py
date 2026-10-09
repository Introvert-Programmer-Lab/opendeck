"""Run a firmware build in Espressif's QEMU and check it end to end.

Uses the virtual boards (firmware/boards/qemu-*): the shared firmware with the
display replaced by a pixel copy and taps fed from the "tap" test command.
Checks that it boots, mounts storage, loads the default deck, answers the
protocol, draws the deck page like the app rendered it, switches pages,
reports key taps and fills the screen exactly.

Needs ESP-IDF's QEMU (python $IDF_PATH/tools/idf_tools.py install qemu-xtensa)
and Pillow.

Run: python tools/qemu_test.py <build dir> <esp32|esp32s3> [--qemu PATH]
The build dir must hold flash.bin, a merged image filled to the flash size:
  python -m esptool --chip esp32 merge_bin --fill-flash-size 4MB -o flash.bin @flash_args
"""
import argparse
import base64
import glob
import io
import json
import os
import socket
import subprocess
import sys
import time
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent


def fnv(data, h=2166136261):
    for b in data:
        h = ((h ^ b) * 16777619) & 0xFFFFFFFF
    return h


class Board:
    def __init__(self, port):
        self.sock = socket.create_connection(("127.0.0.1", port), timeout=1)
        self.buf = b""
        self.partial = ""
        self.events = []
        self.screens = []  # hashes printed by the virtual display, in order

    def _pump(self, timeout):
        self.sock.settimeout(timeout)
        try:
            data = self.sock.recv(65536)
        except socket.timeout:
            return
        if not data:
            raise RuntimeError("QEMU closed the serial port")
        self.buf += data
        while b"\n" in self.buf:
            line, self.buf = self.buf.split(b"\n", 1)
            text = line.decode(errors="replace").strip()
            if text.startswith("QEMU screen "):
                self.screens.append(text.split()[2])
                continue
            if "Guru Meditation" in text or "abort()" in text:
                raise RuntimeError("firmware crashed: " + text)
            # A screen report can split a protocol line in two: rejoin the halves.
            if self.partial:
                text, self.partial = self.partial + text, ""
            if "{" not in text:
                continue
            try:
                msg = json.loads(text[text.index("{"):])
            except ValueError:
                self.partial = text[text.index("{"):]
                continue
            self.events.append(msg)

    def request(self, cmd, timeout=10, want=("ok", "err"), match=None, kick=True):
        """Sends cmd and returns the first reply of a wanted type (and passing match)."""
        self.sock.sendall((json.dumps(cmd) + "\n").encode())
        until = time.time() + timeout
        next_kick = time.time() + 0.3 if kick else float("inf")
        while time.time() < until:
            for i, e in enumerate(self.events):
                if e.get("t") in want and (match is None or match(e)):
                    return self.events.pop(i)
            self._pump(0.2)
            self.events = [e for e in self.events if e.get("t") != "pong"]
            if time.time() > next_kick:
                # QEMU's UART sometimes holds a reply until more input arrives.
                self.sock.sendall(b'{"t":"ping"}\n')
                next_kick = time.time() + 0.3
        raise TimeoutError(f"no reply to {cmd} (events: {self.events[-3:]})")

    def wait_event(self, t, timeout=30):
        until = time.time() + timeout
        kick = time.time() + 1
        while time.time() < until:
            for i, e in enumerate(self.events):
                if e.get("t") == t:
                    return self.events.pop(i)
            self._pump(0.2)
            if time.time() > kick:
                self.sock.sendall(b'{"t":"ping"}\n')
                kick = time.time() + 1
        raise TimeoutError(f"no {t} event")

    def settle(self, quiet=3, timeout=40):
        """Waits until the screen stops changing; returns its hash."""
        until = time.time() + timeout
        n, last_change = len(self.screens), time.time()
        while time.time() < until:
            self._pump(0.2)
            if len(self.screens) != n:
                n, last_change = len(self.screens), time.time()
            elif self.screens and time.time() - last_change >= quiet:
                return self.screens[-1]
        raise TimeoutError("the screen never settled")

    def shot_rows(self, y, n):
        # QEMU's UART now and then loses a reply outright; a read is safe to repeat.
        for _ in range(4):
            try:
                return self.request({"t": "shot", "y": y, "n": n}, timeout=6, match=lambda e: e.get("y") == y)
            except TimeoutError:
                pass
        raise TimeoutError(f"no screenshot row {y} (events: {[{k: v for k, v in e.items() if k != 'd'} for e in self.events[-6:]]})")

    def stable_screenshot(self, w, h, tries=6):
        """Screenshots until two in a row match: the page is fully drawn."""
        last = None
        for _ in range(tries):
            self.settle()
            shot = self.screenshot(w, h)
            if shot == last:
                return shot
            last = shot
        raise TimeoutError("the screen kept changing")

    def screenshot(self, w, h):
        """Returns (raw RGB565, step): boards without PSRAM keep every second pixel."""
        first = self.shot_rows(0, 1)
        step = first.get("s", 1)
        rows = [base64.b64decode(first["d"])]
        y = 1
        while y < h // step:
            n = min(8, h // step - y)
            rows.append(base64.b64decode(self.shot_rows(y, n)["d"]))
            y += n
        return b"".join(rows), step


def rgb565_image(raw, w, h):
    img = Image.new("RGB", (w, h))
    px = img.load()
    for i in range(w * h):
        v = raw[2 * i] | (raw[2 * i + 1] << 8)
        px[i % w, i // w] = ((v >> 11) << 3, ((v >> 5) & 0x3F) << 2, (v & 0x1F) << 3)
    return img


def mean_error(a, b, skip=None):
    """Mean absolute difference per channel, ignoring the box `skip` (x0, y0, x1, y1)."""
    pa, pb = a.load(), b.load()
    total = count = 0
    for y in range(a.height):
        for x in range(a.width):
            if skip and skip[0] <= x < skip[2] and skip[1] <= y < skip[3]:
                continue
            total += sum(abs(p - q) for p, q in zip(pa[x, y], pb[x, y]))
            count += 3
    return total / count


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("build")
    ap.add_argument("chip", choices=["esp32", "esp32s3"])
    ap.add_argument("--qemu")
    ap.add_argument("--port", type=int, default=5555)
    ap.add_argument("--psram", default="8M", help="PSRAM size for the ESP32-S3")
    a = ap.parse_args()
    qemu = a.qemu or next(iter(sorted(glob.glob(os.path.expanduser(
        os.environ.get("IDF_TOOLS_PATH", "~/.espressif") + "/tools/qemu-xtensa/*/qemu/bin/qemu-system-xtensa")))), None)
    if not qemu:
        sys.exit("QEMU not found; install it with idf_tools.py install qemu-xtensa or pass --qemu")
    image = Path(a.build) / "flash.bin"
    # eFuse contents as idf.py qemu sets them (chip revision), and the watchdog
    # timer disabled because QEMU's timer emulation trips it at startup.
    efuse = Path(a.build) / "qemu_efuse.bin"
    if a.chip == "esp32":
        fuses = bytearray(120)
        fuses[13], fuses[22] = 0x80, 0x10
        machine = ["-machine", "esp32", "-m", "4M"]
        efuse_dev = "nvram.esp32.efuse"
    else:
        fuses = bytearray(1024)
        fuses[38] = 0x0C
        machine = ["-machine", "esp32s3", "-m", a.psram]
        efuse_dev = "nvram.esp32c3.efuse"  # QEMU names the S3's eFuse device this way
    efuse.write_bytes(bytes(fuses))
    proc = subprocess.Popen([qemu, "-nographic", *machine, "-drive", f"file={image},if=mtd,format=raw",
                             "-drive", f"file={efuse},if=none,format=raw,id=efuse",
                             "-global", f"driver={efuse_dev},property=drive,value=efuse",
                             "-global", f"driver=timer.{a.chip}.timg,property=wdt_disable,value=true",
                             "-serial", f"tcp::{a.port},server,nowait", "-monitor", "none"],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    failures = []

    def check(ok, what):
        print(("PASS " if ok else "FAIL ") + what)
        if not ok:
            failures.append(what)

    try:
        time.sleep(1.5)
        b = Board(a.port)
        hello = None
        for _ in range(30):
            try:
                hello = b.request({"t": "hello"}, timeout=3, want=("hello",), kick=False)
                break
            except TimeoutError:
                pass
        check(hello is not None, "boots and answers hello")
        if hello is not None:
            time.sleep(2)  # let replies to the earlier hellos drain
            b._pump(0.5)
            b.events.clear()
        if hello is None:
            return 1
        w, h = hello["w"], hello["h"]
        deck_dir = ROOT / "firmware" / "fs_image" / f"{w}x{h}" / "deck"
        manifest = json.loads((deck_dir / "deck.json").read_text())
        check(hello["id"].startswith("qemu-"), f"reports its board id ({hello['id']})")
        check(hello["pages"] == len(manifest["pages"]), f"loaded the default deck ({hello['pages']} pages)")
        check(hello["fs_total"] > 0 and hello["fs_used"] > 0, "storage mounted")

        raw, step = b.stable_screenshot(w, h)
        shot = rgb565_image(raw, w // step, h // step)
        shot.save(Path(a.build) / "qemu_page0.png")
        full = Image.open(deck_dir / manifest["pages"][0]["img"]).convert("RGB")
        want = Image.new("RGB", shot.size)
        want.putdata([full.getpixel((x * step, y * step)) for y in range(shot.height) for x in range(shot.width)])
        dot = manifest.get("dot")
        r = 12
        skip = tuple(v // step for v in (dot[0] - r, dot[1] - r, dot[0] + r, dot[1] + r)) if dot else None  # live dot
        err = mean_error(shot, want, skip)
        check(err < 6, f"page 0 matches the app's rendering (mean error {err:.2f} per channel)")

        b.request({"t": "page", "n": 1})
        raw1, _ = b.stable_screenshot(w, h)
        page1 = rgb565_image(raw1, w // step, h // step)
        err1 = mean_error(page1, shot, skip)
        check(err1 > 6, f"page 1 is drawn instead (differs from page 0 by {err1:.2f})")
        b.request({"t": "page", "n": 0})
        raw0, _ = b.stable_screenshot(w, h)
        back = mean_error(rgb565_image(raw0, w // step, h // step), shot, skip)
        check(back < 1, f"going back to page 0 draws it again (difference {back:.2f})")

        key = manifest["pages"][0]["keys"][0]
        x, y, kw, kh = key["r"]
        b.request({"t": "tap", "x": x + kw // 2, "y": y + kh // 2})
        ev = b.wait_event("key")
        check(ev.get("id") == key["id"], "a tap on the first key reports that key")

        b.request({"t": "get", "f": "deck.json", "o": 0})
        b.request({"t": "fill", "c": 0xF800})
        filled = b.settle()
        row = bytes([0x00, 0xF8]) * w
        want_hash = fnv(b"".join(fnv(row).to_bytes(4, "little") for _ in range(h)))
        check(filled == f"{want_hash:08x}", "fill paints every pixel exactly")
    except Exception as e:  # noqa: BLE001
        check(False, f"{type(e).__name__}: {e}")
    finally:
        proc.kill()
    print(f"{len(failures)} failed" if failures else "all passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
