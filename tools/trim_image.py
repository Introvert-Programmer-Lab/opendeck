"""Copy a merged flash image without its trailing 0xFF padding.

The filesystem image fills its whole partition, so a merged image is about
16 MB even though only the first few MB hold data. The flasher skips blank
regions anyway; trimming just makes the download smaller.

Run: python tools/trim_image.py <merged.bin> <out.bin>
"""
import sys
from pathlib import Path

src, dst = Path(sys.argv[1]), Path(sys.argv[2])
data = src.read_bytes()
end = len(data.rstrip(b"\xff"))
end = min((end + 0xFFF) // 0x1000 * 0x1000, len(data))  # keep whole 4 KB sectors
dst.write_bytes(data[:end])
print(f"{dst.name}: {len(data)} -> {end} bytes")
