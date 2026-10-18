<div align="center">

  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="assets/logo-light.png">
    <img alt="mesa-nouveau-fixes" src="assets/logo-light.png" width="62%">
  </picture>

### Hardware video decoding in Firefox on older NVIDIA GPUs

**Mesa fixes for nouveau, GeForce 8 to 700 series: VA-API that browsers can use, H.264 pictures that match software decoding, no GPU errors on video playback, and GTK 4 menus that draw correctly.**

[![Checks](https://github.com/francesco-stimola/mesa-nouveau-fixes/actions/workflows/checks.yml/badge.svg)](https://github.com/francesco-stimola/mesa-nouveau-fixes/actions/workflows/checks.yml)
[![Latest release](https://img.shields.io/github/v/release/francesco-stimola/mesa-nouveau-fixes?sort=semver&label=release)](https://github.com/francesco-stimola/mesa-nouveau-fixes/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Mesa](https://img.shields.io/badge/Mesa-25.2%20%7C%2026.0%20%7C%20main-green.svg)](#patches)

[The problem](#the-problem) · [Results](#results) · [Before and after](#before-and-after) · [Patches](#patches) · [GPUs](#which-gpus-need-which-patches) · [Install](#install) · [Setup](#setup) · [Known issues](#known-issues)

</div>

---

## The problem

nouveau can decode H.264, MPEG-2 and VC-1 in hardware on GeForce 8 (G84 and
later) to GeForce 700 (Kepler) GPUs. `mpv --hwdec=vaapi-copy` works, but
browsers never use it:

- **Firefox and Chromium only take decoded frames through
  `vaExportSurfaceHandle`.** nouveau decodes into interlaced buffers, with the
  two fields in separate layers, and Mesa refuses to export them. Firefox falls
  back to software decoding, which an older CPU cannot sustain at 1080p.
- **Every video start triggers GPU errors.** The kernel logs
  `gr: TRAP_PROP ... SURF_HEIGHT_OVERRUN` each time a player allocates its
  surfaces.
- **Hardware decoding is lost when the player re-creates its decoder**, as
  Firefox does when a clip loops. The second decoder in a process fails with
  `-EEXIST`, and Firefox turns hardware decoding off for that video.
- **Moving areas of some H.264 videos break into blocks.** On GPUs with VP3
  to VP5 decoders ([which ones](#which-gpus-need-which-patches)), B frames
  that use temporal direct prediction, which YouTube's H.264 streams use in
  places, are decoded wrong in every player.
- **Interlaced and monochrome H.264 comes out wrong.** On the same GPUs,
  streams that mix field pictures with MBAFF frames, as TV broadcasts do,
  decode into blocks and garbage. Monochrome streams are not decoded at all:
  in their place comes an old picture left in video memory.
- **Converted pictures turn green and magenta.** When VA-API converts
  frames to I420 or YV12, as players ask when they cannot use the decoded
  surfaces directly, the V plane gets the U values.
- **Stopping a video can freeze the GPU.** A player that closes its decoder
  while the GPU still works on the last frames leaves the kernel unable to
  stop the decoder's channel (`failed to idle channel`), and the next video
  that starts freezes the display.

Outside video, on GeForce 8 to 300 GPUs:

- **GTK 4 menus and popovers are garbled.** With GTK's default renderer
  (ngl), an open menu and the window behind it are drawn with each other's
  projection, so their content appears shrunken or stretched. The usual
  workaround is `GSK_RENDERER=gl`.

## Results

Measured on a GeForce GT 240M (GT216, VP4), Mesa 25.2.8 as shipped by
Ubuntu 24.04, Firefox 158, GPU at its highest performance level
([GPU clocks](#gpu-clocks)), H.264 High 1080p30 at 5 Mbit/s:

| | Mesa 25.2.8 | Mesa 25.2.8 + these patches |
|---|---|---|
| Decoding in Firefox | software (export fails) | **hardware, zero-copy** |
| Firefox CPU use | 87% of one core | **25%** |
| Frames decoded late, 35 s run | 182 | **4** |
| `SURF_HEIGHT_OVERRUN` at video start | yes | **no** |
| Still decoding in hardware after the clip loops | no | **yes** |

The exported frames match software decoding: a frame shown by
`mpv --hwdec=vaapi` differs from the software-decoded one by 0.05 on average
on a 0–255 scale. Converted to I420 by VA video processing, decoded frames
had a V plane at 7 dB PSNR against software decoding with stock Mesa; with
0007 all three planes match exactly.

Every frame decoded on the same GPU, compared with software decoding by MD5
([how](docs/TESTING.md#8-h264-frames-match-software-decoding-0005)). H.264
decoding is exact, so a correct decoder differs on no frame:

| | Mesa 25.2.8 | Mesa 25.2.8 + these patches |
|---|---|---|
| Big Buck Bunny from YouTube, H.264 720p60, 0:50–1:15 | 143 of 1501 frames differ | **none** |
| Sintel and Tears of Steel from YouTube, H.264 1080p, 25 s each | 13 of 1202 frames differ | **none** |
| FFmpeg's H.264 conformance streams that VP4 decodes | 2834 frames in 49 of 163 streams differ | **50 frames in 1 stream** |

The stream still wrong, `slice2_field_aurora4`, codes field pictures with
the deblocking filter off across slice edges (`disable_deblocking_filter_idc`
2). Its luma differs slightly on some top macroblock edges (50 dB PSNR). The
decoder reads slice headers on its own, so the driver has nothing to pass
for this; it looks like a limit of the hardware or its firmware. The other
14 streams of the suite use Extended profile features or Baseline FMO and
ASO, which ffmpeg does not decode through VA-API.

Uniform buffer updates, same GPU, measured with
[`tests/ubo-two-contexts.c`](tests/ubo-two-contexts.c) (20 batches, each
ending with a readback):

| | Mesa 25.2.8 | Mesa 25.2.8 + these patches |
|---|---|---|
| Two contexts, wrong readbacks | 40 of 40 | **0 of 40** |
| One context orphaning its buffer, wrong readbacks | 20 of 20 | **0 of 20** |
| Menus in Files (GTK 4.14, default renderer) | garbled | **correct** |

## Before and after

Each fix on the same GeForce GT 240M, with a driver that has every patch but
that one and with one that has all of them. Video panels are frames the GPU
decoded; terminal panels show the commands' output, shortened
([how they are made](assets/src/before-after)).

**0001.** Traps in the kernel log every time a video starts:

<p align="center">
  <img src="assets/video-start-traps.gif" width="100%"
       alt="Kernel log after mpv starts a video. Without 0001: SURF_HEIGHT_OVERRUN traps, 35 messages per video start. With 0001: no messages.">
</p>

**0002.** Firefox decodes on the GPU instead of the CPU:

<p align="center">
  <img src="assets/firefox-export.gif" width="100%"
       alt="Firefox decoder log. Without 0002: vaExportSurfaceHandle fails and Firefox decodes 472 frames on the CPU in 20 seconds, some of them late. With 0002: 479 frames decoded on the GPU, none on the CPU.">
</p>

**0003.** A looping clip stays on the GPU:

<p align="center">
  <img src="assets/firefox-loop.gif" width="100%"
       alt="Firefox decoder log of a 10-second clip playing in a loop. Without 0003: 300 frames on the GPU, then the new decoder fails and 569 frames are decoded on the CPU. With 0003: 1040 frames on the GPU in 38 seconds.">
</p>

**0004.** A scripted GTK 4 session with GTK's default renderer, on stock
Mesa and with the patches ([how it is made](assets/src/gtk-menus)). At every
step the window and the menu change together, which is when the bug strikes;
in everyday use the glitches come and go:

<p align="center">
  <img src="assets/gtk-menus.gif" width="100%"
       alt="A GTK 4 window with its main menu open. With stock Mesa the menu is drawn tiny in a corner and parts of the window are stretched; with the patches both are drawn correctly.">
</p>

**0005.** Big Buck Bunny as YouTube serves it in H.264 720p60:

<p align="center">
  <img src="assets/h264-blocks.gif" width="100%"
       alt="Flowers in Big Buck Bunny as the camera moves. Without 0005 blocks appear in the moving areas and spread from frame to frame; with 0005 the picture is clean.">
</p>

**0006.** A decoder stopped half way. The left side is the kernel log from
the day the bug was found: each run hangs the GPU until a reboot.

<p align="center">
  <img src="assets/stopped-decoder.gif" width="100%"
       alt="Kernel log. Without 0006: failed to idle channel and warnings in g84_ectx_bind after players were closed while decoding, and the GPU stays hung. With 0006: two decodes stopped after 20 frames leave no messages.">
</p>

**0007.** Decoded frames converted to I420 by VA video processing:

<p align="center">
  <img src="assets/vpp-colours.gif" width="100%"
       alt="Big Buck Bunny converted to I420. Without 0007 the sky is pink, the grass bright green and the rocks purple; with 0007 the colours are right.">
</p>

**0008.** Traps when a program creates YUYV or UYVY surfaces. Stock Mesa
does not show them: its clears never cover these surfaces, the bug 0001
fixes, and 0001 brings this one out.

<p align="center">
  <img src="assets/yuyv-traps.gif" width="100%"
       alt="Kernel log after uploading a YUYV frame through VA-API. Without 0008: RT_FAULT traps and a trapped write with PAGE_NOT_PRESENT. With 0008: no messages.">
</p>

**0009.** A monochrome conformance stream, next to software decoding.
**Without 0009 the GPU decodes nothing of the video**: what comes out is an
old picture left in video memory, the same every time, unrelated to the
video. With 0009 every frame matches software decoding.

<p align="center">
  <img src="assets/h264-monochrome.gif" width="100%"
       alt="Three panels. Software decoding and With 0009 show the same monochrome video, a man in a hard hat talking. Without 0009 shows an unrelated colour picture of a building site, left in video memory.">
</p>

**0010.** An interlaced conformance stream that mixes field pictures with
MBAFF frames:

<p align="center">
  <img src="assets/h264-interlaced.gif" width="100%"
       alt="A crane against the sky. Without 0010 the picture is washed out and broken into blocks and stripes; with 0010 it is clean.">
</p>

## Patches

Each patch exists for Mesa 25.2 ([`patches/mesa-25.2`](patches/mesa-25.2),
what Ubuntu 24.04 ships), Mesa 26.0 ([`patches/mesa-26.0`](patches/mesa-26.0),
Ubuntu 26.04) and Mesa main ([`patches/mesa-main`](patches/mesa-main), for
upstream review). They apply with `git am` or `patch -p1`.

| Patch | Symptom | Cause | GPUs |
|---|---|---|---|
| **0001** nv50,nvc0: don't read pipe_surface templates as nv50_surface in clears | `SURF_HEIGHT_OVERRUN` traps at every video start; some fields never cleared | The VA frontend clears surfaces with plain `pipe_surface` templates. nv50 and nvc0 read driver fields past the end of the template, so the render target ends up 1 line high. | nv50 and nvc0 drivers |
| **0002** frontends/va: export interlaced surfaces through a progressive copy | `vaExportSurfaceHandle` fails: Firefox decodes in software, `mpv --hwdec=vaapi` needs a conversion | No DRM PRIME layout describes a buffer whose fields sit in two layers | Every GPU nouveau decodes video on (VP2 to VP5) |
| **0003** winsys/nouveau: pass the DRM fd when deleting subchannel objects | Hardware decoding stops when the player re-creates its decoder | Object deletion passes the channel id where the DRM fd belongs, so engine objects leak and the next one fails with `-EEXIST` | Every nouveau GPU, since Mesa 24.1 |
| **0004** nv50: only push constant buffer updates through a current binding | GTK 4 menus drawn shrunken or stretched with the default renderer | Small uniform buffer updates go through a hardware binding point that can still point at the buffer's old storage, after the buffer was orphaned, or at another context's buffer | nv50 driver (GeForce 8 to 300 series) |
| **0005** nouveau: keep H.264 references in the same VP slot | Blocks in moving areas of H.264 videos, spread by B frames used as references | The decoder names the pictures that stored motion vectors point to by their position in the reference list, and players reorder that list at every reference frame, so temporal direct prediction reads the wrong pictures | VP3 to VP5 |
| **0006** nouveau: wait for the video engines before destroying a vp3 decoder | After a video stops early, the next one freezes the GPU | The decoder deletes its engine objects while the engines still work through the last pictures, and the kernel cannot idle the channel | VP3 to VP5 |
| **0007** vl/compositor: render the V plane with its own gfx shaders | Green and magenta colours when VA video processing converts to I420 or YV12 | The shader path renders the V plane with the shaders for both chroma planes, which write U into it | Every GPU nouveau decodes video on, and other drivers without compute video processing |
| **0008** nv50: size surface views by blocks when the block size differs | With 0001, `RT_FAULT` traps when a program creates YUYV or UYVY surfaces, as mpv does when it starts | The VA frontend clears these buffers through RGBA8 views, which hold one block of two pixels per texel. nv50 and nvc0 size the view in pixels, twice the buffer's width. Once 0001 lets clears cover their whole surface, they write past the end of the buffer. | nv50 and nvc0 drivers |
| **0009** nouveau: pass chroma_format_idc to the vp3 H.264 decoder | Monochrome H.264 does not decode | The decoder is always told the stream is 4:2:0 | VP3 to VP5 |
| **0010** nouveau: tell the vp3 H.264 decoder whether a picture is MBAFF | Blocks and garbage in interlaced H.264 that mixes field pictures with MBAFF frames, as TV broadcasts do | The decoder is told that every picture of such a stream is MBAFF coded, field pictures included | VP3 to VP5 |

0002 weaves the two fields into a progressive NV12 copy on the GPU when a
surface is first exported, and refreshes the copy after every decode, video
processing or `vaPutImage` into that surface. Drivers that decode into
progressive buffers never take that path.

None of these patches has been merged into Mesa yet.

### Which GPUs need which patches

nouveau decodes video with a different engine on each GPU generation. The
nouveau chipset (in brackets) is what `vainfo` prints after "for", for
example `NVA5`.

| GPUs | Examples | Video engine | Codecs | 0001 | 0002 | 0003 | 0004 | 0005 | 0006 | 0007 | 0008 | 0009 | 0010 |
|---|---|---|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| G80 (NV50) | GeForce 8800 GTX, 8800 GTS 320/640 | VP1, not supported by nouveau | – | | | | ✓ | | | | | | |
| G84–G96, GT200 (NV84–NVA0) | GeForce 8400 GS (first version), 8500 GT, 8600, 8800 GT, 9400 GT–9800 GTX, GTS 250, GTX 260–295, 8400M–9800M | VP2 | H.264, MPEG-2 | ✓ | ✓ | ✓ | ✓ | | | ✓ | ✓ | | |
| G98, MCP77–MCP7A (NV98, NVAA, NVAC) | GeForce 8400 GS (later versions), 9300 GS, 9200M GS, 9300M GS; integrated GeForce 8200, 8300, 9300, 9400 and ION | VP3 | H.264, MPEG-2, VC-1 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| GT215–GT218, MCP89 (NVA3, NVA5, NVA8, NVAF) | GeForce 210, GT 220, GT 240, 310, 315, G 210M, GT 230M–GT 335M, 320M | VP4 | H.264, MPEG-2, VC-1 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| GF100–GF116 (NVC0–NVCF) | GeForce 400 series, most of the 500 series | VP4 | H.264, MPEG-2, VC-1 | ✓ | ✓ | ✓ | | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| GF117, GF119, Kepler (NVD7, NVD9, NVE4–NV108) | GeForce GT 520, GT 610, Kepler models of the 600 and 700 series such as GT 710, GT 730, GTX 660, GTX 770 | VP5 | H.264, MPEG-2, VC-1 | ✓ | ✓ | ✓ | | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Maxwell and later (NV117 on) | GeForce GTX 745, 750, 750 Ti and later | not supported by nouveau | – | | | | | | | | | | |

0004 fixes the OpenGL driver of every GeForce 8 to 300 GPU, so it matters
with or without video decoding. 0003 changes code every nouveau GPU runs;
the failure it fixes shows up when a program re-creates a video decoder.
VP2 GPUs set the two parameters 0009 and 0010 correct in the same way, in
their own decoder code (`nv84_video_bsp.c`, `nv84_video_vp.c`); these
patches leave it alone, since there was no VP2 GPU to test them on. Some
GeForce 600 and 700 models use Fermi or Maxwell chips: check the chipset
`vainfo` prints.

## Install

On Ubuntu 24.04 and 26.04 and distributions based on them (Zorin OS 18,
Linux Mint 22, ...), the [PPA](https://launchpad.net/~francesco-stimola/+archive/ubuntu/mesa-nouveau-fixes)
has Ubuntu's own Mesa with these patches, for amd64 and i386:

```sh
sudo add-apt-repository ppa:francesco-stimola/mesa-nouveau-fixes
sudo apt update
sudo apt upgrade
```

Then install the firmware, set up Firefox and fix the GPU clocks, as
[Setup](#setup) describes. [`docs/SETUP.md`](docs/SETUP.md) also explains how
to go back to Ubuntu's Mesa.

## Try it without installing

The patches touch the VA driver and the nouveau Gallium driver. For a quick
test, load a patched VA driver for one program and leave the system Mesa
untouched.

**Prebuilt, for Ubuntu 24.04.** Each
[release](https://github.com/francesco-stimola/mesa-nouveau-fixes/releases/latest)
has the driver attached, built from the Mesa source Ubuntu 24.04 ships:

```sh
tar xzf mesa-nouveau-fixes-*-va-driver-ubuntu-24.04.tar.gz
cd mesa-nouveau-fixes-*-va-driver-ubuntu-24.04
LIBVA_DRIVERS_PATH=$PWD LIBVA_DRIVER_NAME=nouveau vainfo
LIBVA_DRIVERS_PATH=$PWD mpv --hwdec=vaapi video.mp4
```

**From source.** On Ubuntu 24.04, with `deb-src` entries enabled:

```sh
sudo apt build-dep mesa
apt source mesa
./scripts/build-va-driver.sh mesa-25.2.8 patches/mesa-25.2 out
LIBVA_DRIVERS_PATH=$PWD/out LIBVA_DRIVER_NAME=nouveau vainfo
```

This driver supports Wayland and DRM displays, which is what Firefox and mpv
use on a Wayland desktop. X11 applications need the full Mesa from the PPA.

0004 fixes the OpenGL driver, which the VA driver above does not replace. Its
effect needs a full Mesa build; [`docs/TESTING.md`](docs/TESTING.md#7-uniform-buffer-updates-reach-their-buffer-0004)
shows how to try one for a single program.

Firefox reads VA drivers only from system directories inside its RDD sandbox.
To test a driver from another directory, also set `MOZ_DISABLE_RDD_SANDBOX=1`
for that run only. The PPA installs the driver in the system directories, so
Firefox needs neither variable.

## Setup

Besides the patched Mesa, a working system needs three things.
[`docs/SETUP.md`](docs/SETUP.md) walks through all of them, with scripts:

- **Firmware.** nouveau needs the video firmware inside NVIDIA's 340.108
  driver, which only NVIDIA may distribute.
  [`scripts/install-firmware.sh`](scripts/install-firmware.sh) downloads the
  driver from nvidia.com, checks it and extracts the firmware with envytools.
- **Firefox.** Use Mozilla's `.deb`: the Snap and Flatpak builds bring their
  own Mesa. Firefox blocks VA-API on NVIDIA GPUs until
  `media.hardware-video-decoding.force-enabled` is true;
  [`scripts/setup-firefox.sh`](scripts/setup-firefox.sh) sets it for every
  profile.
- **GPU clocks**, below.

These decoders handle H.264, MPEG-2 and VC-1 only. VP4 (GT21x) is designed for
H.264 High up to 1080p30 (level 4.1); 1080p60 is beyond it. Sites that serve
VP9 or AV1 need an H.264-only setting, such as the enhanced-h264ify extension
for YouTube.

### GPU clocks

nouveau never changes the GPU clocks on its own: the GPU stays at the
performance level the VBIOS picked at boot, often a middle one. At that level
the decoder may be slower than the CPU, and the patches look as if they did
nothing. Check the current level, marked with `*`, as root:

```sh
sudo cat /sys/kernel/debug/dri/*/pstate
```

Set the fastest level at every boot with the kernel parameter
`nouveau.config=NvClkMode=0xf`, using the highest level your GPU lists; see
[SETUP](docs/SETUP.md#4-gpu-clocks). Levels can be changed on Tesla (GeForce 8
to 300) and most Kepler GPUs.

Do not change levels while the desktop runs. Writing a level to the `pstate`
file works most of the time, but on a GeForce GT 240M switching between levels
when the screen went off and on twice left the GPU broken: once it hung at
once, once it kept failing every frame of the desktop until it hung. Setting
the level at boot avoids both.

## Known issues

- One of FFmpeg's H.264 conformance streams, `slice2_field_aurora4`, still
  differs slightly from software decoding on VP4, probably because of the
  hardware: see [Results](#results). No other stream or video we tested
  does.

## Testing

[`docs/TESTING.md`](docs/TESTING.md) lists the checks used for the results
above: kernel traps, export with mpv, frame comparison with software decoding,
H.264 conformance, decoders stopped early, conversion to three-plane formats,
YUYV and UYVY surfaces, monochrome and interlaced H.264, and Firefox logs.

## License

MIT, like the Mesa files the patches modify. See [LICENSE](LICENSE).
