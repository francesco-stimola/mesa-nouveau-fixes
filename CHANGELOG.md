# Changelog

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
