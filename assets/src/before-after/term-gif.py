#!/usr/bin/env python3
"""Draw two terminal transcripts side by side as a before/after GIF, in the
style of assets/gtk-menus.gif. Lines appear one at a time.

Usage: term-gif.py <before.txt> <after.txt> <out.gif> <patch>

Line prefixes: "$ " command, "! " error, "+ " good, "# " note; the
markers other than "$ " are not drawn.
"""
import sys

from PIL import Image, ImageDraw, ImageFont

before, after, out, patch = sys.argv[1:5]

GAP, BAR, PAD = 16, 52, 16
BG = (246, 246, 247)
TERM = (30, 30, 34)
LABEL_FONT = ImageFont.truetype("/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf", 22)
MONO = ImageFont.truetype("/usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf", 14)
MONO_BOLD = ImageFont.truetype("/usr/share/fonts/truetype/noto/NotoSansMono-Bold.ttf", 14)
LABELS = [
    (f"Without {patch}", (192, 28, 40)),
    (f"With {patch}", (38, 162, 105)),
]
STYLE = {
    "$": ((240, 240, 240), MONO_BOLD),
    "!": ((255, 128, 112), MONO),
    "+": ((110, 214, 150), MONO),
    "#": ((150, 150, 160), MONO),
    "": ((205, 205, 210), MONO),
}
COLS, LINE, TPAD = 72, 21, 14


def parse(path):
    lines = []
    for raw in open(path, encoding="utf-8").read().splitlines():
        kind = raw[:1] if raw[:2] in ("$ ", "! ", "+ ", "# ") else ""
        text = raw if kind in ("$", "") else raw[2:]
        if kind == "#":
            text = "# " + text
        if len(text) > COLS:
            text = text[:COLS - 1] + "…"
        lines.append((kind, text))
    return lines


sides = [parse(before), parse(after)]
rows = max(len(s) for s in sides)
pw = TPAD * 2 + round(MONO.getlength("M") * COLS)
ph = TPAD * 2 + LINE * rows
size = (PAD * 2 + pw * 2 + GAP, BAR + ph + PAD)


def frame(shown):
    canvas = Image.new("RGB", size, BG)
    draw = ImageDraw.Draw(canvas)
    for k, lines in enumerate(sides):
        x = PAD + k * (pw + GAP)
        text, colour = LABELS[k]
        draw.ellipse((x + 2, 19, x + 16, 33), fill=colour)
        draw.text((x + 26, 12), text, font=LABEL_FONT, fill=(40, 40, 46))
        draw.rounded_rectangle((x, BAR, x + pw - 1, BAR + ph - 1), radius=8, fill=TERM)
        for i, (kind, line) in enumerate(lines[:shown]):
            fill, font = STYLE[kind]
            draw.text((x + TPAD, BAR + TPAD + i * LINE), line, font=font, fill=fill)
    return canvas


frames, durations = [], []
for shown in range(0, rows + 1):
    frames.append(frame(shown))
    nxt = [s[shown][0] if shown < len(s) else "" for s in sides]
    durations.append(900 if shown == 0 else 700 if "$" in nxt else 350)
durations[-1] = 4000

palette = frames[-1].quantize(colors=64, method=Image.Quantize.MEDIANCUT)
gif = [f.quantize(palette=palette, dither=Image.Dither.NONE) for f in frames]
gif[0].save(out, save_all=True, append_images=gif[1:], duration=durations,
            loop=0, optimize=True, disposal=1)
print(out, size, len(gif))
