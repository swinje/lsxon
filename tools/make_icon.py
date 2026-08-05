"""Regenerate the iOS app icon set with 'LSX' drawn on top of a circle.

The previous icon had the circle drawn over the text, hiding 'LSX'. This
script draws the background, then the circle, then the 'LSX' text on top.
"""
import os
from PIL import Image, ImageDraw, ImageFont

OUT_DIR = os.path.join(
    os.path.dirname(__file__),
    "..",
    "ios",
    "Runner",
    "Assets.xcassets",
    "AppIcon.appiconset",
)

# Sizes (in points) and scale multipliers, matching Contents.json.
SPECS = [
    ("Icon-App-20x20@1x", 20, 1),
    ("Icon-App-20x20@2x", 20, 2),
    ("Icon-App-20x20@3x", 20, 3),
    ("Icon-App-29x29@1x", 29, 1),
    ("Icon-App-29x29@2x", 29, 2),
    ("Icon-App-29x29@3x", 29, 3),
    ("Icon-App-40x40@1x", 40, 1),
    ("Icon-App-40x40@2x", 40, 2),
    ("Icon-App-40x40@3x", 40, 3),
    ("Icon-App-60x60@2x", 60, 2),
    ("Icon-App-60x60@3x", 60, 3),
    ("Icon-App-76x76@1x", 76, 1),
    ("Icon-App-76x76@2x", 76, 2),
    ("Icon-App-83.5x83.5@2x", 83.5, 2),
    ("Icon-App-1024x1024@1x", 1024, 1),
]

BG = (0, 150, 136)  # teal, matches the app's seed color
CIRCLE = (255, 255, 255)
TEXT = (0, 150, 136)


def load_font(px_size):
    """Find a bold TrueType font, falling back to PIL's default."""
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/HelveticaNeue-Bold.ttf",
        "/Library/Fonts/Arial Bold.ttf",
        "/System/Library/Fonts/Supplemental/Helvetica.ttc",
    ]
    for path in candidates:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, px_size)
            except Exception:
                continue
    return ImageFont.load_default()


def make_icon(size_px):
    img = Image.new("RGBA", (size_px, size_px), BG)
    draw = ImageDraw.Draw(img)

    # Circle centered, ~62% of the canvas.
    margin = size_px * 0.19
    draw.ellipse(
        [margin, margin, size_px - margin, size_px - margin],
        fill=CIRCLE,
    )

    # 'LSX' text on top of the circle, centered.
    font = load_font(int(size_px * 0.34))
    text = "LSX"
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    x = (size_px - tw) / 2 - bbox[0]
    y = (size_px - th) / 2 - bbox[1]
    draw.text((x, y), text, font=font, fill=TEXT)
    return img


def main():
    for name, points, scale in SPECS:
        size_px = int(round(points * scale))
        img = make_icon(size_px)
        path = os.path.join(OUT_DIR, f"{name}.png")
        img.convert("RGB").save(path, "PNG")
        print(f"wrote {path} ({size_px}x{size_px})")


if __name__ == "__main__":
    main()
