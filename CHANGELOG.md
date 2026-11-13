# Changelog

## Unreleased

- **Releases first.** SETUP.md now checks out the latest release after
  cloning, and the PPA takes its patches from the latest release tag
  instead of `main`, which may hold patches still in review in Mesa. The
  PPA workflow also stops when Launchpad does not answer, instead of
  building a `+nvfix1`, and times out stalled uploads.
- **0001, 0012 and 0013, as merged in Mesa.** Dave Airlie asked for 0008
  and 0001 in a merge request of their own,
  [!46135](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/46135),
  approved it on 11 November and merged it on 12 November. The patches here
  now match it: 0001 has the reviewed code and message, and **0013**
  (nv50,nvc0: clear through a driver surface on the stack) goes with it, a
  cleanup Dave suggested that fills the driver surface on the stack
  instead of allocating one at every clear; **0012** (nv30: don't read
  pipe_surface templates as nv30_surface in clears) fixes the same texture
  clears for GeForce FX, 6 and 7, and was only built. On the GT 240M with
  Mesa 25.2.8, checks 2, 11 and 15 gave the same results as before.
- **0003 and 0004 in their own merge request.** They are in
  [!46224](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/46224),
  also at Dave's request, and their messages follow his review: 0003 is now
  "nouveau/winsys: pass the drm fd when deleting subchannel objects", and
  0004 has a Fixes tag. The code is the same.
- **Mesa main.** `patches/mesa-main` leaves out 0001, 0008, 0012 and 0013,
  which are in Mesa main now; the other nine still apply to it. CI applies
  them one at a time, since `git apply` does not chain patches that change
  the same lines.
- **GPUs.** The texture clear fixes reach every GPU nouveau runs OpenGL on,
  not only those it decodes video on: 0012 the NV30 and NV40 families
  (GeForce FX to 7), 0001 and 0013 everything from G80 on, Maxwell and
  later included. The README's GPU tables, its introduction, SETUP.md and
  TESTING.md now say so; such GPUs only need the patched Mesa, not the VA
  driver.
- **Kepler kernel fixes.** The README no longer says whether Risto
  Pajula's kernel fixes are merged: it points to the nouveau list, where
  that can be followed, and to the separate commit that fixes the first
  one in Linux 7.4-rc2.
- **Issues.** Problem reports use a form that asks for the GPU, kernel,
  Mesa and kernel log; questions can still go in a blank issue. The README
  lists what to check before opening one, and where problems outside these
  patches go: the nouveau kernel driver and Mesa have their own trackers.
- **Tests.** [`tests/cleartex.c`](https://github.com/francesco-stimola/mesa-nouveau-fixes/blob/main/tests/cleartex.c)
  and [`tests/clear-test.html`](https://github.com/francesco-stimola/mesa-nouveau-fixes/blob/main/tests/clear-test.html),
  Kush Chandak's reproducers for the `glClearTexImage` bug that 0001 fixes,
  in OpenGL and in WebGL;
  [check 15](https://github.com/francesco-stimola/mesa-nouveau-fixes/blob/main/docs/TESTING.md#15-glclearteximage-clears-textures-0001)
  says how to run them, also on Ubuntu's own Mesa with the PPA installed,
  and what they gave on a GT 710 and on the GT 240M. On the GT 240M, stock
  Mesa 25.2.8 leaves nearly every texel uncleared and the kernel logs
  `DATA_ERROR`; with the patches every texel is right and all 1980 WebGL
  checks pass. The README's results have a row for it.
- **Brave without options.** Brave 1.98 decodes in hardware with nouveau on
  its own: on the GT 240M it picked `VaapiVideoDecoder` and Wayland with no
  options, with the same CPU use as with them. SETUP.md now says how to
  check, and keeps the options for browsers that still need them.
- **0011 on a GT 710.** Kush Chandak confirmed 0011 on a GT 710 (GK208B),
  where Brave's import failed in `eglCreateImage` and the picture was
  garbled; the README and check 14 say so.
- **KDE Plasma.** SETUP.md explains why Chromium-based browsers stop after
  three frames under KDE Plasma on nouveau, a Chromium bug with explicit
  sync, and links Kush Chandak's workaround and the
  [Chromium report](https://issues.chromium.org/issues/582204270).

## 1.5.0 - 2026-11-02

- **Debian and Fedora.** Two new folders of patches:
  [`patches/mesa-26.1`](https://github.com/francesco-stimola/mesa-nouveau-fixes/tree/main/patches/mesa-26.1)
  for Debian 13 with backports and Debian testing, and
  [`patches/mesa-26.2`](https://github.com/francesco-stimola/mesa-nouveau-fixes/tree/main/patches/mesa-26.2)
  for Debian unstable and Fedora 44 and 45; `patches/mesa-26.0` also fits
  Fedora 43. They make the same changes as the other folders; in 26.2, 0002
  refreshes the exported copy after `vaPutImage` once video processing has
  finished, as 26.2 waits for it there. On the GT 240M, the VA drivers built
  from both folders decode, convert, upload and export frames exactly as the
  25.2 one does, with no kernel errors.
  [`scripts/build-debian-package.sh`](https://github.com/francesco-stimola/mesa-nouveau-fixes/blob/main/scripts/build-debian-package.sh)
  and [`scripts/build-fedora-package.sh`](https://github.com/francesco-stimola/mesa-nouveau-fixes/blob/main/scripts/build-fedora-package.sh)
  rebuild the distribution's own Mesa packages with the patches, on Fedora
  with the H.264 decoder that Fedora leaves out.
  [`docs/SETUP.md`](https://github.com/francesco-stimola/mesa-nouveau-fixes/blob/main/docs/SETUP.md#1-mesa-with-the-patches)
  says which folder fits which distribution and how to build; the README's
  Install section lists the ways in short.
- **CI.** Every folder is checked against the Mesa source of the
  distributions it is for, their own patches included: the patches must
  apply without fuzz, as `dpkg-source` and `rpmbuild` require, and the VA
  driver must build. A Packages workflow, run by hand, follows the Debian
  and Fedora steps to the end and installs the packages.
- **Upstream.** 0011 joined the other patches in Mesa
  [!45340](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/45340),
  with Youssef Mahmoud's Tested-by: all eleven are in review.

## 1.4.0 - 2026-11-02

- **0011** nvc0: accept tiled modifiers for planar YUV formats. On GF100
  and later GPUs, Brave and other Chromium-based browsers, and Electron apps
  such as Discord, decode in hardware: before, their GPU process could not
  import the decoded frames (`gbm_bo_import` failed), kept restarting, and
  playback fell back to software decoding. Youssef Mahmoud reported it and
  tested the fix on a GK104
  ([check 14](https://github.com/francesco-stimola/mesa-nouveau-fixes/blob/main/docs/TESTING.md#14-brave-imports-decoded-frames-0011));
  the README shows it before and after with Brave's logs from that GPU.
- **README.** Each fix now has one place: a short description with its
  before/after GIF, grouped by what users see. The results are one table,
  the patch table shows which ones are in review upstream, and the GPU
  table has a row per patch, so new patches add rows instead of columns.
  Two badges show the versions the PPA has now for Ubuntu 24.04 and 26.04;
  they refresh at most once an hour, so a slow answer from Launchpad no
  longer turns them into a grey error badge as often.
- **0001 and WebGL.** Since Mesa 25.2, `glClearTexImage` reaches the clear
  hooks that 0001 fixes with a template on the stack, so 0001 also fixes
  OpenGL texture clears: on Kepler, WebGL in Chromium-based browsers crashed
  the GPU process. Kush Chandak found this and tested it on a GeForce GT
  710, where Kush also confirmed hardware decoding with all ten patches. The
  message of 0001 now says so, with `Fixes: 718e277ab56e`; the README marks
  0001 for G80 too and notes the two kernel fixes Kepler needs, with the
  kernel versions that need them (6.2 and 6.6). SETUP.md says which desktop
  the Brave options were tested on: Brave showed no frames under KDE Plasma
  on Kepler. On a GK104, Youssef Mahmoud also decodes H.264 in hardware with
  the patches and the kernel fixes, in Firefox and mpv, and with 0011 in
  Brave and Discord too.
- **Upstream.** 0007, 0009 and 0010 joined the other patches in Mesa
  [!45340](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/45340):
  all ten are in review. The series builds on Mesa main without warnings.
- **Brave.** [`docs/SETUP.md`](https://github.com/francesco-stimola/mesa-nouveau-fixes/blob/main/docs/SETUP.md#brave-and-other-chromium-browsers)
  shows the options that make Brave decode in hardware, tested with Brave
  1.97, and how to keep them in its launchers. Other Chromium-based browsers
  take the same options.
- **H.264 conformance.** The last stream that differed from software
  decoding, `slice2_field_aurora4`, was a bug of FFmpeg before 8.0, which
  decodes it wrongly ([ticket 11360](https://trac.ffmpeg.org/ticket/11360)).
  The GPU's frames match FFmpeg's reference checksums, with and without the
  patches. With all the patches no conformance stream differs now; stock
  Mesa gets 48 of them wrong. The known issue in the README is gone, and
  [check 8](https://github.com/francesco-stimola/mesa-nouveau-fixes/blob/main/docs/TESTING.md#8-h264-frames-match-software-decoding-0005)
  shows how to compare that stream with the reference.
- **PPA.** [ppa:francesco-stimola/mesa-nouveau-fixes](https://launchpad.net/~francesco-stimola/+archive/ubuntu/mesa-nouveau-fixes)
  has all eleven patches for Ubuntu 24.04 and 26.04: `sudo apt upgrade`
  installs them.

## 1.3.0 - 2026-10-18

- **0007** vl/compositor: render the V plane with its own gfx shaders. VA
  video processing to I420 or YV12 no longer turns pictures green and
  magenta on drivers that use Mesa's shader path for it, nouveau included:
  the V plane got U. Converted frames now match software decoding on every
  plane ([check 10](https://github.com/francesco-stimola/mesa-nouveau-fixes/blob/main/docs/TESTING.md#10-conversion-to-three-plane-formats-keeps-the-colours-0007)).
  The known issue in the README is gone.
- **0008** nv50: size surface views by blocks when the block size differs.
  Since 0001, clears of YUYV and UYVY surfaces covered twice the buffer's
  width and wrote past its end: `RT_FAULT` traps in the kernel log whenever
  a program created such surfaces, 6 lines each time mpv started with
  `--hwdec=vaapi`. Stock Mesa does not show them, because its clears never
  reach these surfaces. Now there are none.
- **0009** nouveau: pass chroma_format_idc to the vp3 H.264 decoder.
  Monochrome H.264 decodes on VP3 to VP5; before, none of its frames came
  out.
- **0010** nouveau: tell the vp3 H.264 decoder whether a picture is MBAFF.
  Interlaced H.264 that mixes field pictures with MBAFF frames, as TV
  broadcasts do, no longer decodes into blocks and garbage on VP3 to VP5.
- **H.264 conformance.** With all the patches, 1 of the 163 streams VP4
  decodes still differs from software decoding, by 50 frames, against 49
  streams and 2834 frames with stock Mesa; the README explains the one
  left. [`tests/h264-conformance.sh`](https://github.com/francesco-stimola/mesa-nouveau-fixes/blob/main/tests/h264-conformance.sh)
  now compares whole coded pictures (`-apply_cropping 0`): ffmpeg cannot
  crop the top or left of frames it downloads from the GPU, so
  `CVFC1_Sony_C`, which crops, counted as wrong for every driver.
- **Before and after.** The README shows every fix in a GIF, with a driver
  that has all the patches but that one and with one that has all of them
  ([how they are made](https://github.com/francesco-stimola/mesa-nouveau-fixes/tree/main/assets/src/before-after)).
- **PPA.** [ppa:francesco-stimola/mesa-nouveau-fixes](https://launchpad.net/~francesco-stimola/+archive/ubuntu/mesa-nouveau-fixes)
  has all ten patches for Ubuntu 24.04 and 26.04: `sudo apt upgrade`
  installs them.

## 1.2.0 - 2026-10-18

- **0005** nouveau: keep H.264 references in the same VP slot. Moving
  areas of H.264 videos no longer break into blocks on GPUs with VP3 to VP5
  decoders: B frames with temporal direct prediction now match software
  decoding frame for frame.
- **Which GPUs need which patches.** A table in the README maps GPU
  families and models to their video engine and to the patches that apply.
  [`tests/h264-conformance.sh`](https://github.com/francesco-stimola/mesa-nouveau-fixes/blob/main/tests/h264-conformance.sh)
  compares every frame of FFmpeg's H.264 conformance streams with software
  decoding.
- **0006** nouveau: wait for the video engines before destroying a vp3
  decoder. Stopping a video while the GPU still decodes it no longer leaves
  the decoder hung for the next one. This was also behind the GPU freezes
  the README listed as "two programs decoding at once": with 0006, two
  programs decode at the same time without problems, and that known issue
  is gone.
- **PPA.** [ppa:francesco-stimola/mesa-nouveau-fixes](https://launchpad.net/~francesco-stimola/+archive/ubuntu/mesa-nouveau-fixes)
  has the Mesa of Ubuntu 24.04 and 26.04 with the patches, for amd64 and
  i386. A daily workflow rebuilds it when Ubuntu updates Mesa
  ([`ppa/series`](https://github.com/francesco-stimola/mesa-nouveau-fixes/blob/main/ppa/series),
  [`scripts/ppa-upload.sh`](https://github.com/francesco-stimola/mesa-nouveau-fixes/blob/main/scripts/ppa-upload.sh)).
- **Mesa 26.0.** [`patches/mesa-26.0`](https://github.com/francesco-stimola/mesa-nouveau-fixes/tree/main/patches/mesa-26.0)
  has the patches for Mesa 26.0, as shipped by Ubuntu 26.04. 0002 calls
  26.0's video processing interface; the others are unchanged. They
  are build-tested only: the results in the README were measured with Mesa
  25.2. The checks now build the VA driver from each PPA series' Mesa.
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
