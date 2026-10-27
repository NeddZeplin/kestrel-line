"""Compose foliage card textures from the CC0 element atlases in textures/foliage.

- oak_spray.png:   leafy twig built from the six LeafSet016 oak leaves
- pine_spray.png:  needled pine branch built from the PineNeedles001 bundles, tinted green
- grass_clump.png: fan of Foliage008 grass blades

Run from the project root:  python -I tools/compose_foliage.py
"""
import math
import random
from collections import deque

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

SRC = "textures/foliage/"


def elements(path, min_px=400):
    """Cut an atlas into its separate elements (connected blobs of alpha)."""
    img = Image.open(path).convert("RGBA")
    w, h = img.size
    s = 4
    small = img.getchannel("A").resize((w // s, h // s))
    mask = small.load()
    sw, sh = small.size
    seen = [[False] * sw for _ in range(sh)]
    out = []
    for y in range(sh):
        for x in range(sw):
            if seen[y][x] or mask[x, y] < 40:
                continue
            q = deque([(x, y)])
            seen[y][x] = True
            x0 = x1 = x
            y0 = y1 = y
            n = 0
            while q:
                cx, cy = q.popleft()
                n += 1
                x0, x1, y0, y1 = min(x0, cx), max(x1, cx), min(y0, cy), max(y1, cy)
                for dx in (-2, -1, 0, 1, 2):
                    for dy in (-2, -1, 0, 1, 2):
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < sw and 0 <= ny < sh and not seen[ny][nx] and mask[nx, ny] >= 40:
                            seen[ny][nx] = True
                            q.append((nx, ny))
            if n * s * s >= min_px:
                out.append(img.crop((x0 * s - 4, y0 * s - 4, x1 * s + 8, y1 * s + 8)))
    return out


def tint(el, rgb, keep=0.35):
    """Recolour an element: luminance detail kept, hue taken from rgb."""
    r, g, b, a = el.split()
    lum = Image.merge("RGB", (r, g, b)).convert("L")
    lum = ImageEnhance.Contrast(lum).enhance(1.3)
    col = Image.new("RGB", el.size, rgb)
    shaded = Image.composite(col, Image.new("RGB", el.size, (0, 0, 0)), lum.point(lambda v: int(80 + v * 0.7)))
    base = Image.blend(shaded, Image.merge("RGB", (r, g, b)), keep)
    base.putalpha(a)
    return base


def paste(canvas, el, cx, cy, angle, scale, bright=1.0):
    e = el.resize((max(1, int(el.width * scale)), max(1, int(el.height * scale))), Image.LANCZOS)
    if bright != 1.0:
        rgb = ImageEnhance.Brightness(e.convert("RGB")).enhance(bright)
        rgb.putalpha(e.getchannel("A"))
        e = rgb
    e = e.rotate(angle, resample=Image.BICUBIC, expand=True)
    canvas.alpha_composite(e, (int(cx - e.width / 2), int(cy - e.height / 2)))


def bleed(img):
    """Spread edge colour into transparent pixels so mipmaps don't halo white."""
    rgb = img.convert("RGB")
    a = img.getchannel("A")
    blurred = rgb.filter(ImageFilter.GaussianBlur(12))
    filled = Image.composite(rgb, blurred, a.point(lambda v: 255 if v > 8 else 0))
    filled.putalpha(a)
    return filled


def oak_spray(rng):
    leaves = elements(SRC + "oak_leaves.png", 20000)
    S = 1024
    c = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(c)
    # twig from the bottom centre, branching
    twigs = [((S / 2, S - 10), (S / 2 + 20, S * 0.15))]
    for t in (0.3, 0.5, 0.68, 0.82):
        y = S - 10 - (S - 160) * t
        for side in (-1, 1):
            twigs.append(((S / 2 + 6, y), (S / 2 + side * S * (0.42 - t * 0.25), y - S * 0.12)))
    for (x0, y0), (x1, y1) in twigs:
        d.line([(x0, y0), (x1, y1)], fill=(72, 58, 40, 255), width=7)
    for (x0, y0), (x1, y1) in twigs:
        for k in range(9):
            t = 0.25 + k / 9 * 0.8
            x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
            ang = math.degrees(math.atan2(-(y1 - y0), x1 - x0)) - 90 + rng.uniform(-70, 70)
            paste(c, rng.choice(leaves), x + rng.uniform(-30, 30), y + rng.uniform(-30, 30), ang, rng.uniform(0.17, 0.26), rng.uniform(0.62, 1.0))
    # darken and green up a little: summer oak rather than spring
    rgb = ImageEnhance.Color(c.convert("RGB")).enhance(1.15)
    rgb = ImageEnhance.Brightness(rgb).enhance(0.78)
    rgb.putalpha(c.getchannel("A"))
    return bleed(rgb)


def pine_spray(rng):
    bundles = elements(SRC + "pine_needles.png", 6000)
    greens = [(40, 78, 30), (32, 66, 26), (50, 90, 36), (28, 58, 24)]
    S = 1024
    c = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(c)
    # main shoot runs left to right (the card is laid along the branch), with side shoots
    shoots = [((20, S / 2), (S - 30, S / 2 - 30))]
    for t in (0.2, 0.38, 0.56, 0.72):
        x = 20 + (S - 50) * t
        for side in (-1, 1):
            shoots.append(((x, S / 2 - 30 * t), (x + S * 0.22 * (1 - t * 0.4), S / 2 + side * S * 0.3 * (1 - t * 0.5))))
    for (x0, y0), (x1, y1) in shoots:
        d.line([(x0, y0), (x1, y1)], fill=(84, 62, 42, 255), width=6)
    for (x0, y0), (x1, y1) in shoots:
        n = int(math.hypot(x1 - x0, y1 - y0) / 9)
        base = math.degrees(math.atan2(-(y1 - y0), x1 - x0))
        for k in range(n):
            t = k / max(n - 1, 1)
            x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
            for side in (-1, 1):
                el = tint(rng.choice(bundles), rng.choice(greens), 0.12)
                ang = base + side * rng.uniform(25, 60)
                # bundles grow from their left end; offset so the base sits on the shoot
                sc = rng.uniform(0.2, 0.3) * (1.0 - t * 0.35)
                dx = math.cos(math.radians(ang)) * el.width * sc / 2
                dy = -math.sin(math.radians(ang)) * el.width * sc / 2
                paste(c, el, x + dx, y + dy, ang, sc, rng.uniform(0.75, 1.1))
    return bleed(c)


def grass_clump(rng):
    blades = elements(SRC + "grass_blades.png", 6000)
    S = 1024
    c = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    for i in range(46):
        el = rng.choice(blades)
        # blades lie horizontally in the atlas with the root on the left; stand them up
        ang = 90 + rng.uniform(-28, 28)
        sc = S * rng.uniform(0.62, 0.98) / el.width
        h = el.width * sc
        cx = S / 2 + rng.uniform(-S * 0.18, S * 0.18)
        x = cx + math.cos(math.radians(ang)) * h / 2
        y = S - 8 - math.sin(math.radians(ang)) * h / 2
        paste(c, el, x, y, ang, sc, rng.uniform(0.6, 1.05))
    rgb = ImageEnhance.Brightness(c.convert("RGB")).enhance(0.85)
    rgb.putalpha(c.getchannel("A"))
    return bleed(rgb)


if __name__ == "__main__":
    rng = random.Random(7)
    for name, fn in (("oak_spray", oak_spray), ("pine_spray", pine_spray), ("grass_clump", grass_clump)):
        img = fn(rng)
        img.save(SRC + name + ".png", optimize=True)
        prev = Image.new("RGB", img.size, (255, 255, 255))
        prev.paste(img.convert("RGB"), mask=img.getchannel("A"))
        prev.thumbnail((512, 512))
        prev.save("shots/" + name + "_preview.jpg")
        print(name, img.size)
