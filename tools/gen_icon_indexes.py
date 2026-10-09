"""Build the icon libraries bundled with the app.

- assets/icons/simple_icons.json.gz  Simple Icons (CC0): [title, slug, hex, svgPath] for every brand
- assets/icons/dashboard_icons.json.gz  Dashboard Icons (Apache-2.0) index: [name, base, aliases]
  (images are downloaded on demand from jsDelivr and cached by the app)
- assets/default_icons/*.png  official icons used by the default deck

usage: python tools/gen_icon_indexes.py <simple-icons package dir> <dashboard metadata.json>
"""
import gzip, json, re, sys, urllib.request
from pathlib import Path

root = Path(__file__).resolve().parents[1]
si_pkg, dash_meta = Path(sys.argv[1]), Path(sys.argv[2])

data = json.loads((si_pkg / "data/simple-icons.json").read_text(encoding="utf-8"))
icons = data["icons"] if isinstance(data, dict) else data

def slug_of(title):  # simple-icons slug rules
    s = title.lower().replace("+", "plus").replace(".", "dot").replace("&", "and")
    for a, b in (("đ","d"),("ħ","h"),("ı","i"),("ĸ","k"),("ŀ","l"),("ł","l"),("ß","ss"),("ŧ","t")):
        s = s.replace(a, b)
    import unicodedata
    s = unicodedata.normalize("NFD", s)
    return re.sub(r"[^a-z0-9]", "", s)

rows = []
for ic in icons:
    slug = ic.get("slug") or slug_of(ic["title"])
    f = si_pkg / "icons" / f"{slug}.svg"
    if not f.exists():
        continue
    path = re.search(r' d="([^"]+)"', f.read_text(encoding="utf-8")).group(1)
    rows.append([ic["title"], slug, ic["hex"], path])
(root / "assets/icons/simple_icons.json.gz").write_bytes(gzip.compress(json.dumps(rows, separators=(",", ":")).encode(), 9))
print("simple icons:", len(rows))

meta = json.loads(dash_meta.read_text(encoding="utf-8"))
dash = [[name, m.get("base", "svg"), m.get("aliases", [])] for name, m in sorted(meta.items())]
(root / "assets/icons/dashboard_icons.json.gz").write_bytes(gzip.compress(json.dumps(dash, separators=(",", ":"), ensure_ascii=False).encode(), 9))
print("dashboard icons:", len(dash))

for name in ["google-chrome", "windows-explorer", "visual-studio-code", "spotify", "discord", "youtube"]:
    url = f"https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/{name}.png"
    (root / f"assets/default_icons/{name}.png").write_bytes(urllib.request.urlopen(url).read())
    print("default:", name)
