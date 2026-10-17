# Changelog

## 1.2.0 - Unreleased

- **PPA.** [ppa:francesco-stimola/mesa-nouveau-fixes](https://launchpad.net/~francesco-stimola/+archive/ubuntu/mesa-nouveau-fixes)
  has Ubuntu 24.04's Mesa with the patches, for amd64 and i386. A daily
  workflow rebuilds it when Ubuntu updates Mesa
  ([`ppa/series`](https://github.com/francesco-stimola/mesa-nouveau-fixes/blob/main/ppa/series),
  [`scripts/ppa-upload.sh`](https://github.com/francesco-stimola/mesa-nouveau-fixes/blob/main/scripts/ppa-upload.sh)).
- **Setup guide.** [`docs/SETUP.md`](https://github.com/francesco-stimola/mesa-nouveau-fixes/blob/main/docs/SETUP.md)
  covers everything besides Mesa: `scripts/install-firmware.sh` extracts the
  video firmware from NVIDIA's driver, `scripts/setup-firefox.sh` enables
  hardware decoding in Firefox for every profile, and the GPU clocks are set
  at boot.
- **GPU clocks.** Changing the performance level while the desktop runs hung
  or broke a GeForce GT 240M in tests: the README now says to set it at boot
  only.

## 1.1.0 - 2026-10-17

- **0004** nv50: only push constant buffer updates through a current binding.
  GTK 4 menus and popovers draw correctly with the default ngl renderer on
  GeForce 8 to 300 GPUs, without `GSK_RENDERER=gl`.
- [`tests/ubo-two-contexts.c`](tests/ubo-two-contexts.c) reproduces the bug
  0004 fixes without GTK.
- The README shows the GTK fix in a before/after GIF.

The attached VA driver includes 0004, but its effect is in the OpenGL driver,
which needs a full Mesa build.

## 1.0.0 - 2026-10-17

First release. The patches exist for Mesa 25.2, as shipped by Ubuntu 24.04,
and for Mesa main.

- **0001** nv50,nvc0: don't read pipe_surface templates as nv50_surface in
  clears. Video players no longer raise `SURF_HEIGHT_OVERRUN` traps when they
  allocate their surfaces.
- **0002** frontends/va: export interlaced surfaces through a progressive copy.
  `vaExportSurfaceHandle` works on nouveau, so Firefox decodes in hardware and
  `mpv --hwdec=vaapi` no longer needs a conversion.
- **0003** winsys/nouveau: pass the DRM fd when deleting subchannel objects.
  A process can destroy a video decoder and create a new one, so Firefox keeps
  hardware decoding when a clip loops.

Attached files:

- the nouveau VA driver, built from Ubuntu 24.04's Mesa 25.2 with the patches,
  to test with `LIBVA_DRIVERS_PATH` (Wayland and DRM displays only);
- the patches.
