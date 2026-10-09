"""Upload a deck folder (deck.json + images) to an OpenDeck board over USB, using the app's protocol.

uv run --with pyserial python tools/deck_push.py COM6 firmware/fs_image/320x480/deck
"""
import base64, json, sys, time
from pathlib import Path
import serial

port, folder = sys.argv[1], Path(sys.argv[2])
s = serial.Serial()
s.port, s.baudrate, s.timeout = port, 921600, 5  # UART boards; native USB ignores it
s.dtr = s.rts = False
s.open()
buf = b""

def req(obj):
    global buf
    s.write((json.dumps(obj) + "\n").encode())
    while True:
        while b"\n" not in buf:
            chunk = s.read(max(1, s.in_waiting))
            if not chunk: raise TimeoutError(obj.get("t"))
            buf += chunk
        line, buf = buf.split(b"\n", 1)
        i = line.find(b"{")
        if i < 0: continue
        r = json.loads(line[i:])
        if r.get("t") in ("ok", "err", "hello", "pong"):
            if r["t"] == "err": raise RuntimeError(r)
            return r

files = sorted(folder.iterdir(), key=lambda p: p.name == "deck.json")
t0 = time.time()
req({"t": "begin"})
total = 0
for f in files:
    data = f.read_bytes(); total += len(data)
    req({"t": "put", "f": f.name, "n": len(data)})
    for o in range(0, len(data), 3072):
        req({"t": "data", "d": base64.b64encode(data[o:o + 3072]).decode()})
req({"t": "commit"})
dt = time.time() - t0
h = req({"t": "hello"})
print(f"pushed {len(files)} files, {total // 1024} KB in {dt:.1f}s ({total / 1024 / dt:.0f} KB/s); device reports pages={h['pages']} fs_used={h['fs_used']}")
