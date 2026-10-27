"""Generate seamless camouflage textures for vehicle paint, one per biome.

- woodland.png: four-colour woodland (light green, field drab, forest green, black), for temperate sectors
- desert.png:   three-colour desert (sand, khaki, brown)
- winter.png:   white / grey disruptive pattern

Run from the project root:  python -I tools/make_camo.py
"""
import random

from PIL import Image, ImageFilter

S = 512


def smooth_noise(rng, cells, octave_weights):
    """Tileable smooth noise in 0..255: random grid tiled 3x3, upscaled, centre cropped."""
    acc = None
    for cells_n, w in zip(cells, octave_weights):
        small = Image.new("L", (cells_n, cells_n))
        small.putdata([rng.randrange(256) for _ in range(cells_n * cells_n)])
        tiled = Image.new("L", (cells_n * 3, cells_n * 3))
        for i in range(3):
            for j in range(3):
                tiled.paste(small, (i * cells_n, j * cells_n))
        big = tiled.resize((S * 3, S * 3), Image.BICUBIC).crop((S, S, 2 * S, 2 * S))
        big = big.filter(ImageFilter.GaussianBlur(2))
        acc = big if acc is None else Image.blend(acc, big, w)
    return acc


def pattern(seed, layers, base):
    """layers: [(colour, cells, threshold)] painted in order wherever that layer's noise exceeds threshold."""
    rng = random.Random(seed)
    img = Image.new("RGB", (S, S), base)
    for colour, cells, thr in layers:
        n = smooth_noise(rng, [cells, cells * 2], [0.35])
        mask = n.point(lambda v, t=thr: 255 if v > t else 0)
        img.paste(Image.new("RGB", (S, S), colour), (0, 0), mask)
    # A little grain so large blotches don't read as flat plastic.
    grain = smooth_noise(rng, [96], [1.0])
    return Image.blend(img, Image.merge("RGB", (grain, grain, grain)), 0.06)


if __name__ == "__main__":
    out = "textures/camo/"
    import os
    os.makedirs(out, exist_ok=True)
    # Woodland: light green base, then field drab, forest green and black blotches.
    pattern(11, [((104, 84, 56), 6, 150), ((52, 66, 38), 7, 140), ((28, 28, 24), 9, 182)], (98, 112, 64)).save(out + "woodland.png")
    pattern(23, [((176, 150, 110), 5, 135), ((128, 100, 70), 7, 160)], (206, 188, 150)).save(out + "desert.png")
    pattern(37, [((186, 191, 190), 6, 140), ((120, 126, 124), 8, 170), ((70, 75, 74), 11, 196)], (232, 235, 233)).save(out + "winter.png")
    sheet = Image.new("RGB", (S * 3, S))
    for i, n in enumerate(["woodland", "desert", "winter"]):
        sheet.paste(Image.open(out + n + ".png"), (i * S, 0))
    sheet.resize((768, 256)).save("shots/camo_preview.jpg")
    print("ok")
