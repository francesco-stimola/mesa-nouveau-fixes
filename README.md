<div align="center">

  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="assets/logo-light.png">
    <img alt="mesa-nouveau-fixes" src="assets/logo-light.png" width="62%">
  </picture>

### Hardware video decoding in Firefox on older NVIDIA GPUs

**Mesa fixes for nouveau, GeForce 8 to 700 series: VA-API that browsers can use, no GPU errors on video playback, and GTK 4 menus that draw correctly.**

[![Checks](https://github.com/francesco-stimola/mesa-nouveau-fixes/actions/workflows/checks.yml/badge.svg)](https://github.com/francesco-stimola/mesa-nouveau-fixes/actions/workflows/checks.yml)
[![Latest release](https://img.shields.io/github/v/release/francesco-stimola/mesa-nouveau-fixes?sort=semver&label=release)](https://github.com/francesco-stimola/mesa-nouveau-fixes/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Mesa](https://img.shields.io/badge/Mesa-25.2%20%7C%20main-green.svg)](#patches)

[The problem](#the-problem) · [Results](#results) · [Patches](#patches) · [Try it](#try-it) · [Requirements](#requirements) · [Known issues](#known-issues)

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
on a 0–255 scale.

Uniform buffer updates, same GPU, measured with
[`tests/ubo-two-contexts.c`](tests/ubo-two-contexts.c) (20 batches, each
ending with a readback):

| | Mesa 25.2.8 | Mesa 25.2.8 + these patches |
|---|---|---|
| Two contexts, wrong readbacks | 40 of 40 | **0 of 40** |
| One context orphaning its buffer, wrong readbacks | 20 of 20 | **0 of 20** |
| Menus in Files (GTK 4.14, default renderer) | garbled | **correct** |

## Patches

Each patch exists for Mesa 25.2 ([`patches/mesa-25.2`](patches/mesa-25.2),
what Ubuntu 24.04 ships) and for Mesa main ([`patches/mesa-main`](patches/mesa-main),
for upstream review). They apply with `git am` or `patch -p1`.

| Patch | Symptom | Cause | GPUs |
|---|---|---|---|
| **0001** nv50,nvc0: don't read pipe_surface templates as nv50_surface in clears | `SURF_HEIGHT_OVERRUN` traps at every video start; some fields never cleared | The VA frontend clears surfaces with plain `pipe_surface` templates. nv50 and nvc0 read driver fields past the end of the template, so the render target ends up 1 line high. | nv50 and nvc0 drivers |
| **0002** frontends/va: export interlaced surfaces through a progressive copy | `vaExportSurfaceHandle` fails: Firefox decodes in software, `mpv --hwdec=vaapi` needs a conversion | No DRM PRIME layout describes a buffer whose fields sit in two layers | Every GPU nouveau decodes video on (VP2 to VP5) |
| **0003** winsys/nouveau: pass the DRM fd when deleting subchannel objects | Hardware decoding stops when the player re-creates its decoder | Object deletion passes the channel id where the DRM fd belongs, so engine objects leak and the next one fails with `-EEXIST` | Every nouveau GPU, since Mesa 24.1 |
| **0004** nv50: only push constant buffer updates through a current binding | GTK 4 menus drawn shrunken or stretched with the default renderer | Small uniform buffer updates go through a hardware binding point that can still point at the buffer's old storage, after the buffer was orphaned, or at another context's buffer | nv50 driver (GeForce 8 to 300 series) |

0002 weaves the two fields into a progressive NV12 copy on the GPU when a
surface is first exported, and refreshes the copy after every decode, video
processing or `vaPutImage` into that surface. Drivers that decode into
progressive buffers never take that path.

None of these patches has been merged into Mesa yet.

## Try it

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
use on a Wayland desktop. X11 applications need a full Mesa build, such as the
planned Ubuntu package.

0004 fixes the OpenGL driver, which the VA driver above does not replace. Its
effect needs a full Mesa build; [`docs/TESTING.md`](docs/TESTING.md#7-uniform-buffer-updates-reach-their-buffer-0004)
shows how to try one for a single program.

Firefox reads VA drivers only from system directories inside its RDD sandbox.
To test a driver from another directory, also set `MOZ_DISABLE_RDD_SANDBOX=1`
for that run only. A packaged build that replaces the system Mesa is planned
(Ubuntu PPA).

## Requirements

**Firmware.** nouveau needs the video firmware NVIDIA ships inside its 340.xx
driver. This repository does not contain it: extract it with
[envytools](https://github.com/envytools/envytools/tree/master/vp) and copy the
files to `/lib/firmware/nouveau`. `vainfo` then lists the H.264, MPEG-2 and
VC-1 profiles.

**Firefox.** Firefox blocks VA-API on NVIDIA GPUs. Set
`media.hardware-video-decoding.force-enabled` to `true` in `about:config`.
Snap and Flatpak builds bring their own Mesa: use a build that runs on the
system Mesa, such as the Mozilla `.deb`.

**Formats.** These decoders handle H.264, MPEG-2 and VC-1 only. VP4 (GT21x)
is designed for H.264 High up to 1080p30 (level 4.1); 1080p60 is beyond it.
Sites that serve VP9 or AV1 need an H.264-only setting, such as the
enhanced-h264ify extension for YouTube.

### GPU clocks

nouveau never changes the GPU clocks on its own: the GPU stays at the
performance level the VBIOS picked at boot, often a middle one. At that level
the decoder may be slower than the CPU, and the patches look as if they did
nothing. Check the current level, marked with `*`, as root:

```sh
cat /sys/kernel/debug/dri/*/pstate
```

To switch at runtime, write a level from that list, for example
`echo 0f > /sys/kernel/debug/dri/<card>/pstate`. To set it at every boot, add
`nouveau.config=NvClkMode=0xf` to the kernel command line, using the highest
level your GPU lists. Manual levels work on Tesla (GeForce 8 to 300) and most
Kepler GPUs.

## Known issues

- **Two programs decoding at once can hang the GPU.** When a second process
  starts a hardware decoder while another one is decoding, the kernel driver
  can time out in `g84_ectx_bind` and the display freezes. This happens with
  the stock Mesa as well and needs a kernel fix. Until then, avoid
  hardware-decoded playback in two programs at the same time.
- **Video processing to three-plane formats swaps chroma.** Mesa's shader path
  writes U into the V plane when converting an interlaced surface to I420 or
  YV12, so the colours are wrong. With 0002, mpv no longer needs that
  conversion; a fix is planned.

## Testing

[`docs/TESTING.md`](docs/TESTING.md) lists the checks used for the results
above: kernel traps, export with mpv, frame comparison with software decoding,
and Firefox logs.

## License

MIT, like the Mesa files the patches modify. See [LICENSE](LICENSE).
