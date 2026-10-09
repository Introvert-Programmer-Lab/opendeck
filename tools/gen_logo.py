"""Draw the OpenDeck logo and write every icon the app and firmware use.

The mark is a 2x2 key grid where one key is a ring: three keys and the "O"
of OpenDeck. Everything is drawn with Pillow, so no SVG renderer is needed.

Run: uv run --with pillow python tools/gen_logo.py
"""
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]

LIME = (0xCC, 0xFF, 0x00)
INK = (0x0A, 0x10, 0x0E)
CREAM = (0xFB, 0xFF, 0xE9)

# Mark geometry on a 100 x 100 grid.
KEY = 42
GAP = 12
OFF = (100 - 2 * KEY - GAP) / 2
RADIUS = 11
SQUARES = [(OFF, OFF), (OFF, OFF + KEY + GAP), (OFF + KEY + GAP, OFF + KEY + GAP)]
CIRCLE = (OFF + KEY + GAP + KEY / 2, OFF + KEY / 2, KEY / 2)
RING = 10.5


def mark_svg(fill="#CCFF00", circle_fill=None):
    circle_fill = circle_fill or fill
    rects = "\n".join(
        f'  <rect x="{x:g}" y="{y:g}" width="{KEY}" height="{KEY}" rx="{RADIUS}" fill="{fill}"/>' for x, y in SQUARES
    )
    cx, cy, r = CIRCLE
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">\n'
        f"{rects}\n"
        f'  <circle cx="{cx:g}" cy="{cy:g}" r="{r - RING / 2:g}" fill="none" stroke="{circle_fill}" stroke-width="{RING:g}"/>\n'
        "</svg>\n"
    )


def icon_svg():
    inner = mark_svg("#CCFF00", "#FBFFE9").split("\n", 1)[1].rsplit("</svg>", 1)[0]
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">\n'
        '  <rect width="100" height="100" rx="22" fill="#0A100E"/>\n'
        '  <g transform="translate(20 20) scale(0.6)">\n'
        f"{inner}"
        "  </g>\n"
        "</svg>\n"
    )


def draw_mark(d, x0, y0, size, color, circle_color=None):
    s = size / 100
    for x, y in SQUARES:
        d.rounded_rectangle(
            (x0 + x * s, y0 + y * s, x0 + (x + KEY) * s, y0 + (y + KEY) * s), radius=RADIUS * s, fill=color
        )
    cx, cy, r = CIRCLE
    d.ellipse(
        (x0 + (cx - r) * s, y0 + (cy - r) * s, x0 + (cx + r) * s, y0 + (cy + r) * s),
        outline=circle_color or color,
        width=round(RING * s),
    )


def render(size, full_bleed=False, mark_scale=0.6):
    """Supersampled render. full_bleed fills the whole square (iOS masks it itself)."""
    ss = 4
    big = size * ss
    im = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if full_bleed:
        d.rectangle((0, 0, big, big), fill=INK)
    else:
        d.rounded_rectangle((0, 0, big - 1, big - 1), radius=big * 0.22, fill=INK)
    m = big * mark_scale
    o = (big - m) / 2
    draw_mark(d, o, o, m, LIME, CREAM)
    return im.resize((size, size), Image.LANCZOS)


def main():
    logo = root / "assets/logo"
    logo.mkdir(parents=True, exist_ok=True)
    (logo / "opendeck_mark.svg").write_text(mark_svg())
    (logo / "opendeck_icon.svg").write_text(icon_svg())
    render(1024).save(logo / "app_icon_1024.png")

    tray = render(64, mark_scale=0.72)
    tray.save(logo / "tray.png")
    tray.save(logo / "tray.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64)])

    # Windows exe icon
    render(256).save(
        root / "windows/runner/resources/app_icon.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (256, 256)]
    )

    # Android launcher icons (legacy square icons, drawn full bleed on the dark tile)
    for folder, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        render(px, mark_scale=0.62).save(root / f"android/app/src/main/res/mipmap-{folder}/ic_launcher.png")

    # macOS app icon set
    for px in (16, 32, 64, 128, 256, 512, 1024):
        render(px).save(root / f"macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{px}.png")

    # iOS app icon set: opaque squares, the system rounds the corners
    ios = root / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for f in ios.glob("Icon-App-*.png"):
        base, scale = f.stem.removeprefix("Icon-App-").split("@")
        px = round(float(base.split("x")[0]) * int(scale.rstrip("x")))
        render(px, full_bleed=True).convert("RGB").save(f)

    docs = root / "docs/assets"
    docs.mkdir(parents=True, exist_ok=True)
    (docs / "logo.svg").write_text(icon_svg())
    print("wrote logo, app icons, tray icons")


if __name__ == "__main__":
    main()
