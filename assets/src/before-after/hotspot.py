#!/usr/bin/env python3
"""Find the w x h window where two PNG sequences differ the most.

Usage: hotspot.py <dir a> <dir b> <w> <h>
Prints the top-left corner (multiple of 16) and the share of differing
pixels in that window, summed over all frames.
"""
import os
import sys

from PIL import Image, ImageChops

a_dir, b_dir, w, h = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
acc = None
for name in sorted(os.listdir(a_dir)):
    a = Image.open(os.path.join(a_dir, name)).convert('L')
    b = Image.open(os.path.join(b_dir, name)).convert('L')
    d = ImageChops.difference(a, b).point(lambda v: 255 if v > 12 else 0)
    small = d.resize((a.width // 16, a.height // 16), Image.Resampling.BOX)
    px = list(small.getdata())
    acc = px if acc is None else [x + y for x, y in zip(acc, px)]
W, H = a.width // 16, a.height // 16
bw, bh = w // 16, h // 16
best = (-1, 0, 0)
for y in range(0, H - bh + 1):
    for x in range(0, W - bw + 1):
        s = sum(acc[(y + j) * W + x + i] for j in range(bh) for i in range(bw))
        if s > best[0]:
            best = (s, x, y)
s, x, y = best
print(f'{x * 16} {y * 16} score={s} of {len(os.listdir(a_dir))} frames')
