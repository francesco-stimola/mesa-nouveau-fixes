#!/usr/bin/env python3
"""Put the before/after captures of capture.py side by side in a GIF.

Usage: compose.py <capture dir> <frames> <output.gif>
"""
import sys

from PIL import Image, ImageDraw, ImageFont

src, count, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
CROP = (8, 8, 688, 412)
GAP, BAR, PAD = 16, 52, 16
BG = (246, 246, 247)
FONT = ImageFont.truetype("/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf", 22)
LABELS = [
    ("Mesa 25.2.8, as shipped", (192, 28, 40)),
    ("Mesa 25.2.8 + mesa-nouveau-fixes", (38, 162, 105)),
]

w, h = CROP[2] - CROP[0], CROP[3] - CROP[1]
size = (PAD * 2 + w * 2 + GAP, BAR + h + PAD)
frames = []
for i in range(count):
    canvas = Image.new("RGB", size, BG)
    draw = ImageDraw.Draw(canvas)
    for k, tag in enumerate(("before", "after")):
        x = PAD + k * (w + GAP)
        shot = Image.open(f"{src}/{tag}-{i:02d}.png").convert("RGB").crop(CROP)
        canvas.paste(shot, (x, BAR))
        text, colour = LABELS[k]
        draw.ellipse((x + 2, 19, x + 16, 33), fill=colour)
        draw.text((x + 26, 12), text, font=FONT, fill=(40, 40, 46))
    frames.append(canvas)

# One palette for every frame, so colours do not shift between frames.
sample = Image.new("RGB", (size[0], size[1] * len(frames)))
for i, frame in enumerate(frames):
    sample.paste(frame, (0, i * size[1]))
palette = sample.quantize(colors=192, method=Image.Quantize.MEDIANCUT)
gif = [f.quantize(palette=palette, dither=Image.Dither.NONE) for f in frames]
durations = [900] * count
durations[0] = 1400
durations[-1] = 1800
gif[0].save(out, save_all=True, append_images=gif[1:], duration=durations,
            loop=0, optimize=True, disposal=1)
print(out, size)
