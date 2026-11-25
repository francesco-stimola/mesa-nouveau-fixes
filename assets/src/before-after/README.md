# Before/after GIFs

How the GIFs in the README's [Fixes](../../../README.md#fixes) section were
made, on a GeForce GT 240M with Ubuntu's Mesa 25.2.8. "Without"
is a VA driver built with [`scripts/build-va-driver.sh`](../../../scripts/build-va-driver.sh)
from every patch but that one; "with" is built from all of them.

## Video panels

[`grab.sh`](grab.sh) decodes a whole clip through VA-API with the given
driver and saves some of its frames as PNG; [`video-gif.py`](video-gif.py)
crops both sequences and puts them side by side. [`hotspot.py`](hotspot.py)
finds the area where two sequences differ the most, which is how the crop of
`h264-blocks.gif` was chosen.

`bbb-yt.mp4` is 0:50–1:15 of Big Buck Bunny as YouTube serves it in H.264
720p60. The `.264` streams come from FFmpeg's H.264 conformance suite, which
[`tests/h264-conformance.sh`](../../../tests/h264-conformance.sh) downloads.
`$WITHOUT` is the driver without the patch, `$WITH` the one with all of them.

```sh
# 0005
sh grab.sh $WITHOUT bbb-yt.mp4 1380 1499 4 before
sh grab.sh $WITH bbb-yt.mp4 1380 1499 4 after
python3 video-gif.py before after h264-blocks.gif 0005 112 272 640 360 1.0 66

# 0007: frames converted to I420 by VA video processing
VPP=scale_vaapi=format=yuv420p,hwdownload,format=yuv420p
sh grab.sh $WITHOUT bbb-yt.mp4 600 719 6 before $VPP
sh grab.sh $WITH bbb-yt.mp4 600 719 6 after $VPP
python3 video-gif.py before after vpp-colours.gif 0007 0 0 1280 720 0.5 100

# 0009, with software decoding as a reference
sh grab.sh sw FRext_HPCVMOLQ_BRCM_B.264 0 99 10 sw
sh grab.sh $WITHOUT FRext_HPCVMOLQ_BRCM_B.264 0 99 10 before
sh grab.sh $WITH FRext_HPCVMOLQ_BRCM_B.264 0 99 10 after
python3 video-gif.py --ref sw \
        --note "Without 0009 the GPU decodes nothing of this video and outputs an old picture left in video memory instead." \
        before after h264-monochrome.gif 0009 0 0 352 288 1.25 250

# 0010
sh grab.sh $WITHOUT FRext_HPCAMAPALQ_BRCM_B.264 196 235 2 before
sh grab.sh $WITH FRext_HPCAMAPALQ_BRCM_B.264 196 235 2 after
python3 video-gif.py before after h264-interlaced.gif 0010 0 0 352 288 1.25 100

# 0014: without it the video engine hangs on frame 16, so both drivers
# decode only the first 15 frames (the driver without 0014 has 0006)
FRAMES=15 sh grab.sh $WITHOUT SMM0015.rcv 0 14 1 before
FRAMES=15 sh grab.sh $WITH SMM0015.rcv 0 14 1 after
python3 video-gif.py before after vc1-main.gif 0014 0 0 720 576 0.6 200

# 0015: mpv, which falls back to software decoding when the driver refuses
# the pictures
for s in before:$WITHOUT after:$WITH; do
  LIBVA_DRIVERS_PATH=${s#*:} mpv --no-config --hwdec=vaapi-copy --vo=image \
    --vo-image-format=png --vo-image-outdir=${s%%:*} --frames=20 --no-audio SA10143.vc1
done
python3 video-gif.py --note "With 0015 the driver refuses these pictures and mpv decodes them in software." \
        before after vc1-interlaced.gif 0015 0 0 720 480 0.6 200
```

`SMM0015.rcv` (VC-1 Main) and `SA10143.vc1` (VC-1 Advanced, field
interlaced) come from [FFmpeg's test suite](https://fate-suite.ffmpeg.org/vc1/).

## Terminal panels

[`term-gif.py`](term-gif.py) draws two terminal transcripts side by side:

```sh
python3 term-gif.py term/0001-before.txt term/0001-after.txt video-start-traps.gif 0001
```

The transcripts in [`term`](term) are the output of the commands at their
top, run with each driver and shortened by hand: long lines are cut to fit,
and repeated Firefox log lines are counted instead of listed. The left side
of 0006 is the kernel log from 17 October 2026, when the bug was found, not a
new run: every run of that bug hangs the GPU until a reboot.

0011 changes nothing on the GT 240M. Its transcripts are Youssef Mahmoud's
Brave logs on a Kepler GK104, attached to
[issue #2](https://github.com/francesco-stimola/mesa-nouveau-fixes/issues/2)
and used with his permission: Mesa main with the other ten patches, then
with all eleven. The last lines on the right come from his screenshot of
`brave://media-internals`.

```sh
python3 term-gif.py term/0011-before.txt term/0011-after.txt brave-import.gif 0011
```

0016's transcripts are the output of
[`tests/va-export-size.c`](../../../tests/va-export-size.c) on the GT 240M,
with every patch but 0016 and with all sixteen. The warning on the left is
the one GStreamer's VA plugin prints for each plane when the size is 0, as
reported in [issue #5](https://github.com/francesco-stimola/mesa-nouveau-fixes/issues/5).

```sh
python3 term-gif.py term/0016-before.txt term/0016-after.txt export-size.gif 0016
```
