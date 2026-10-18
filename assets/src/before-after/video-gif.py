#!/usr/bin/env python3
"""Put two sequences of decoded frames side by side in a before/after GIF,
in the style of assets/gtk-menus.gif.

Usage: video-gif.py [--ref <software dir>] [--note <text>] <before dir>
                    <after dir> <out.gif> <patch> <x> <y> <w> <h> [scale]
                    [frame ms]

The frames are cropped to w x h at (x, y), then scaled by `scale`. With
--ref, a first panel shows the same frames decoded in software; --note adds
a line of text under the panels.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

args = sys.argv[1:]
ref = note = None
while args[0] in ("--ref", "--note"):
    if args[0] == "--ref":
        ref = args[1]
    else:
        note = args[1]
    args = args[2:]
before, after, out, patch = args[0:4]
x, y, w, h = (int(v) for v in args[4:8])
scale = float(args[8]) if len(args) > 8 else 1.0
ms = int(args[9]) if len(args) > 9 else 66

GAP, BAR, PAD = 16, 52, 16
BG = (246, 246, 247)
FONT = ImageFont.truetype("/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf", 22)
NOTE_FONT = ImageFont.truetype("/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf", 20)
NOTE = 40 if note else 0
LABELS = [
    (f"Without {patch}", (192, 28, 40)),
    (f"With {patch}", (38, 162, 105)),
]
sources = [before, after]
if ref:
    LABELS.insert(0, ("Software decoding", (110, 110, 120)))
    sources.insert(0, ref)

pw, ph = round(w * scale), round(h * scale)
size = (PAD * 2 + pw * len(sources) + GAP * (len(sources) - 1), BAR + ph + PAD + NOTE)
names = sorted(os.listdir(before))
frames = []
for name in names:
    canvas = Image.new("RGB", size, BG)
    draw = ImageDraw.Draw(canvas)
    if note:
        draw.text((PAD + 2, BAR + ph + 12), note, font=NOTE_FONT, fill=(40, 40, 46))
    for k, src in enumerate(sources):
        px = PAD + k * (pw + GAP)
        shot = Image.open(os.path.join(src, name)).convert("RGB").crop((x, y, x + w, y + h))
        if scale != 1.0:
            shot = shot.resize((pw, ph), Image.Resampling.LANCZOS)
        canvas.paste(shot, (px, BAR))
        text, colour = LABELS[k]
        draw.ellipse((px + 2, 19, px + 16, 33), fill=colour)
        draw.text((px + 26, 12), text, font=FONT, fill=(40, 40, 46))
    frames.append(canvas)

# One palette for every frame, so colours do not shift between frames.
step = max(1, len(frames) // 12)
picked = frames[::step]
sample = Image.new("RGB", (size[0], size[1] * (len(picked) + 1)), BG)
for i, frame in enumerate(picked):
    sample.paste(frame, (0, i * size[1]))
# Large swatches keep the label colours exact in the palette.
swatch = ImageDraw.Draw(sample)
for k, colour in enumerate([c for _, c in LABELS] + [(40, 40, 46)]):
    swatch.rectangle((k * 200, len(picked) * size[1], k * 200 + 199, len(picked) * size[1] + size[1] - 1), fill=colour)
palette = sample.quantize(colors=255, method=Image.Quantize.MEDIANCUT)
gif = [f.quantize(palette=palette, dither=Image.Dither.NONE) for f in frames]
durations = [ms] * len(gif)
durations[0] = max(ms, 1000)
durations[-1] = max(ms, 1500)
gif[0].save(out, save_all=True, append_images=gif[1:], duration=durations,
            loop=0, optimize=True, disposal=1)
print(out, size, len(gif), os.path.getsize(out) // 1024, "KB")
