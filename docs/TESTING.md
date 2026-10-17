# Testing

The checks behind the results in the [README](../README.md). They need a GPU
with nouveau video decoding, the firmware installed, and a VA driver built
with [`scripts/build-va-driver.sh`](../scripts/build-va-driver.sh). In the
commands below, `$NVFIX` is the directory that holds the patched
`nouveau_drv_video.so`.

Run every check twice: once without `LIBVA_DRIVERS_PATH` (stock Mesa) and once
with `LIBVA_DRIVERS_PATH=$NVFIX`.

## Before you start

- **Clocks.** Set the highest performance level, see
  [GPU clocks](../README.md#gpu-clocks). At the boot level the decoder can be
  slower than the CPU and every comparison is skewed.
- **One decoder at a time.** Do not run two hardware-decoding programs at
  once: see [Known issues](../README.md#known-issues).
- **Test videos within the decoder's limits.** VP4 is designed for H.264 High
  up to 1080p30. Encode test clips that match what websites serve, for example
  from Big Buck Bunny:

  ```sh
  ffmpeg -i input.mp4 -an -c:v libx264 -profile:v high -level 4.1 \
         -pix_fmt yuv420p -b:v 5M -maxrate 8M -bufsize 10M -g 60 -refs 4 \
         bbb-1080p30-5M.mp4
  ffmpeg -i input-60fps.mp4 -an -vf scale=1280:720 -c:v libx264 \
         -profile:v high -level 4.0 -pix_fmt yuv420p -b:v 4M -maxrate 6M \
         -bufsize 8M -g 120 -refs 4 bbb-720p60-4M.mp4
  ```

## 1. The driver loads

```sh
LIBVA_DRIVERS_PATH=$NVFIX LIBVA_DRIVER_NAME=nouveau vainfo
```

The driver version ends in `-nvfix`, and the H.264, MPEG-2 and VC-1 profiles
are listed. Without them, the firmware is missing.

## 2. No GPU traps at video start (0001)

In one terminal:

```sh
journalctl -kf | grep --line-buffered SURF_HEIGHT_OVERRUN
```

In another:

```sh
mpv --no-config --hwdec=vaapi-copy --vo=null --ao=null --length=3 bbb-1080p30-5M.mp4
```

Stock Mesa prints `TRAP_PROP ... SURF_HEIGHT_OVERRUN` lines; the patched
driver prints none.

## 3. Surfaces can be exported (0002)

```sh
mpv --no-config --hwdec=vaapi -v bbb-1080p30-5M.mp4 2>&1 | grep -E 'autoconvert|Using hardware'
```

Stock Mesa cannot export the decoded NV12 surfaces, so mpv inserts a
conversion: `[autoconvert] Converting vaapi[nv12] -> vaapi[yuv420p]`. With the
patched driver only `Using hardware decoding (vaapi)` remains.

## 4. Exported frames match software decoding (0002)

Save this as `shot.lua`. It takes a screenshot of the window, as the GPU
rendered it, then quits:

```lua
mp.register_event("playback-restart", function()
  mp.add_timeout(1.5, function()
    mp.commandv("screenshot-to-file", os.getenv("SHOT"), "window")
    mp.command("quit")
  end)
end)
```

Capture the same frame decoded in software and through the exported surface:

```sh
SHOT=sw.png mpv --no-config --hwdec=no --pause --start=5.5 --geometry=960x540 --script=shot.lua bbb-1080p30-5M.mp4
SHOT=hw.png LIBVA_DRIVERS_PATH=$NVFIX mpv --no-config --hwdec=vaapi --pause --start=5.5 --geometry=960x540 --script=shot.lua bbb-1080p30-5M.mp4
```

Compare the two images, for example with ImageMagick:
`compare -metric MAE sw.png hw.png null:`. The patched driver differs by
rounding only (on average 0.05 on a 0–255 scale in our runs). With stock Mesa,
the conversion mpv falls back to swaps the chroma planes, and the colours are
visibly wrong.

## 5. Firefox decodes in hardware (0002, 0003)

Use a separate profile with these prefs in its `user.js`:

```js
user_pref("media.hardware-video-decoding.force-enabled", true);
user_pref("media.autoplay.default", 0);
```

Play a looping clip from a local page, for example
`<video src="bbb-1080p30-5M.mp4" autoplay loop muted>`, and log the decoder:

```sh
MOZ_LOG="timestamp,FFmpegVideo:4,MediaFormatReader:4" MOZ_LOG_FILE=/tmp/fflog \
  firefox --no-remote --profile ./test-profile file://$PWD/play.html
```

To load the patched driver from `$NVFIX`, add `LIBVA_DRIVERS_PATH=$NVFIX` and
`MOZ_DISABLE_RDD_SANDBOX=1`: the RDD sandbox only lets the decoder read
system directories.

What to look for in `/tmp/fflog*`:

| Line | Stock Mesa | Patched |
|---|---|---|
| `VA-API FFmpeg init successful` | yes | yes |
| `vaExportSurfaceHandle failed` | yes, at the first frame | no |
| `VA-API frame pts=...` | none | one per decoded frame |
| `Video decode error, disable HW acceleration` | — | not even after loops |
| `slow decode: failed to decode in time` | many | a few at start-up |

To compare CPU use, sum the CPU time of every process whose executable is in
the Firefox directory over the same 20 seconds of playback, for both drivers.

## 6. Decoders can be re-created (0003)

Loop a short clip for at least 30 seconds (check 5). Each loop destroys the
decoder and creates a new one. Stock Mesa never gets this far in Firefox, so
build a driver with 0001 and 0002 only: there the second decoder fails,
`vaRenderPicture` returns `VA_STATUS_ERROR_ALLOCATION_FAILED` (visible with
`LIBVA_TRACE=/tmp/vatrace/t`), and Firefox turns hardware decoding off. With
all three patches every loop keeps `VA-API frame` lines coming.

## 7. Uniform buffer updates reach their buffer (0004)

0004 is in the OpenGL driver, so this check needs a Mesa build with EGL and
OpenGL ES, not the VA driver. To try it on one program without replacing the
system Mesa, build with a version suffix and load the two libraries through
`LD_LIBRARY_PATH`:

```sh
cd mesa-25.2.8        # with the patches applied
echo 25.2.8-nvfix > VERSION
meson setup build -Dbuildtype=release -Dplatforms=wayland \
      -Dgallium-drivers=nouveau -Dvulkan-drivers=[] -Dglvnd=enabled \
      -Degl=enabled -Dgles2=enabled -Dglx=disabled -Dgallium-va=disabled \
      -Dllvm=disabled
ninja -C build
mkdir -p $HOME/nvfix-gl
cp build/src/egl/libEGL_mesa.so.0 build/src/gallium/targets/dri/libgallium-*.so $HOME/nvfix-gl/
```

Build and run the reproducer:

```sh
cc -O2 tests/ubo-two-contexts.c -o ubo-two-contexts -ldl
./ubo-two-contexts 20 20 8 2 1
./ubo-two-contexts 20 20 8 1 1
LD_LIBRARY_PATH=$HOME/nvfix-gl ./ubo-two-contexts 20 20 8 2 1
LD_LIBRARY_PATH=$HOME/nvfix-gl ./ubo-two-contexts 20 20 8 1 1
```

The first line printed names the driver: the patched one reports
`Mesa 25.2.8-nvfix`. Stock Mesa gets every readback wrong: with two contexts
each one shows the other's colour or black, and with one context it shows an
older colour. The patched driver gets them all right.

With GTK 4, open a menu in any application with the default renderer, for
example the main menu in Files. Files keeps running in the background, so
quit it first; otherwise the new window opens in the old process, with the
old driver:

```sh
nautilus -q
LD_LIBRARY_PATH=$HOME/nvfix-gl GSK_RENDERER=ngl nautilus
```

Stock Mesa draws the menu and the window behind it shrunken or stretched; the
patched driver draws them like `GSK_RENDERER=gl` does.
