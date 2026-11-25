"""Draws the app icon (a stack of cards, the front one saying GIF) into the asset catalog. Needs Pillow.

    python tools/make_icon.py
"""
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

SIZE = 1024
K = 3                       # drawn larger, then scaled down, for smooth edges
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "App", "Assets.xcassets",
                   "AppIcon.appiconset", "AppIcon-1024.png")

TOP = (255, 92, 138)        # background, top left
BOTTOM = (255, 150, 64)     # background, bottom right
CARD = (255, 255, 255)
INK = (238, 62, 118)


def px(*values):
    return tuple(round(v * K) for v in values)


def background():
    small = Image.new("RGB", (64, 64))
    for y in range(64):
        for x in range(64):
            t = (x + y) / 126
            small.putpixel((x, y), tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)))
    return small.resize((SIZE * K, SIZE * K), Image.BICUBIC).convert("RGBA")


def card(image, box, radius, fill, shadow=0):
    if shadow:
        layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
        ImageDraw.Draw(layer).rounded_rectangle(px(box[0], box[1] + 22, box[2], box[3] + 22), radius=radius * K,
                                                fill=(120, 20, 40, shadow))
        image.alpha_composite(layer.filter(ImageFilter.GaussianBlur(24 * K)))
    layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle(px(*box), radius=radius * K, fill=fill)
    image.alpha_composite(layer)


def font(size):
    for name in ("ariblk.ttf", "arialbd.ttf", "DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def main():
    image = background()
    # Two cards behind, each a little narrower and higher, like a pile seen from the front.
    card(image, (292, 246, 732, 420), 70, (255, 255, 255, 90))
    card(image, (232, 298, 792, 500), 84, (255, 255, 255, 160))
    card(image, (168, 356, 856, 800), 104, CARD + (255,), shadow=110)

    draw = ImageDraw.Draw(image)
    text = "GIF"
    face = font(250 * K)
    left, top, right, bottom = draw.textbbox((0, 0), text, font=face)
    x = (SIZE * K - (right - left)) / 2 - left
    y = (356 + 800) / 2 * K - (bottom - top) / 2 - top
    draw.text((x, y), text, font=face, fill=INK)

    icon = image.resize((SIZE, SIZE), Image.LANCZOS).convert("RGB")   # an app icon has no transparency
    icon.save(OUT, optimize=True)
    print("wrote", os.path.normpath(OUT), icon.size)


if __name__ == "__main__":
    main()
