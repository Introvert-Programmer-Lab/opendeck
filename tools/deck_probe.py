"""Talk to an OpenDeck board over USB: send JSON commands, print every line received.

uv run --with pyserial python tools/deck_probe.py COM6 '{"t":"hello"}' --listen 5
"""
import argparse, json, sys, time
import serial

ap = argparse.ArgumentParser()
ap.add_argument("port")
ap.add_argument("cmds", nargs="*")
ap.add_argument("--listen", type=float, default=2.0, help="seconds to keep printing after the last command")
a = ap.parse_args()

s = serial.Serial()
s.port, s.baudrate, s.timeout = a.port, 921600, 0.1  # UART boards; native USB ignores it
s.dtr = False  # on USB-Serial/JTAG, RTS/DTR drive reset and boot mode: keep both released
s.rts = False
s.open()

def pump(seconds):
    end = time.time() + seconds
    buf = b""
    while time.time() < end:
        buf += s.read(4096)
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            line = line.strip()
            if line:
                print("<", line.decode("utf-8", "replace")[:600])

for c in a.cmds:
    print(">", c)
    s.write((c + "\n").encode())
    pump(0.6)
pump(a.listen)
s.close()
