# Setup

What a GeForce 8 to 700 GPU on nouveau needs for hardware video decoding in
Firefox and Brave and a glitch-free GTK 4 desktop, in a Wayland session. The
steps were made on Ubuntu 24.04 (Zorin OS 18); section 1 also covers Debian
and Fedora.

1. [Mesa with the patches](#1-mesa-with-the-patches)
2. [Video firmware](#2-video-firmware)
3. [Browsers](#3-browsers): [Firefox](#firefox), [Brave](#brave-and-other-chromium-browsers)
4. [GPU clocks](#4-gpu-clocks)
5. [Check that it works](#5-check-that-it-works)

Run the scripts from a clone of this repository:

```sh
git clone https://github.com/francesco-stimola/mesa-nouveau-fixes.git
cd mesa-nouveau-fixes
```

## 1. Mesa with the patches

Each distribution ships its own Mesa version, and each folder in
[`patches`](../patches) fits one of them:

| Distribution | Mesa | How | Patches |
|---|---|---|---|
| Ubuntu 24.04 and 26.04, and distributions based on them | 25.2, 26.0 | [the PPA](#ubuntu-the-ppa) | – |
| Debian 13 with backports, Debian testing | 26.1 | [rebuild Debian's packages](#debian) | `mesa-26.1` |
| Debian unstable | 26.2 | [rebuild Debian's packages](#debian) | `mesa-26.2` |
| Fedora 43 | 25.3 | [rebuild Fedora's packages](#fedora) | `mesa-26.0` |
| Fedora 44 and 45 | 26.2 | [rebuild Fedora's packages](#fedora) | `mesa-26.2` |
| any | | [try the VA driver without installing](#try-it-without-installing) | the nearest |

Debian 13 itself ships Mesa 25.0, which no folder fits: its backports have
26.1. `vainfo` shows the Mesa version a system has, as in
`Mesa Gallium driver 26.2.6 for NVA5`.

### Ubuntu: the PPA

The [PPA](https://launchpad.net/~francesco-stimola/+archive/ubuntu/mesa-nouveau-fixes)
has Ubuntu's own Mesa with these patches, for amd64 and i386, so 32-bit games
and Wine get them too:

```sh
sudo add-apt-repository ppa:francesco-stimola/mesa-nouveau-fixes
sudo apt update
sudo apt upgrade
```

Its versions add `+nvfixN` to Ubuntu's, for example
`25.2.8-0ubuntu0.24.04.4+nvfix1`, so apt prefers them. When Ubuntu releases a
new Mesa, the PPA rebuilds it with the patches within a day; until then apt
installs Ubuntu's version, without them.

To go back to Ubuntu's Mesa:

```sh
sudo apt install ppa-purge
sudo ppa-purge ppa:francesco-stimola/mesa-nouveau-fixes
```

### Debian

[`scripts/build-debian-package.sh`](../scripts/build-debian-package.sh)
rebuilds Debian's own Mesa packages with the patches: it downloads the source
of Debian's `mesa` package, adds the patches to its `debian/patches` and
builds every package, as Debian does. On a 4-core machine that takes about
20 minutes, several times more on an older dual-core one, and about 12 GB
of disk space, the build dependencies included. After installing the
packages, the `mesa-nvfix` folder (8 to 9 GB) can be deleted.

apt needs the source entries. On Debian 13, add the backports too:

```sh
sudo sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/debian.sources
printf '%s\n' 'Types: deb deb-src' 'URIs: http://deb.debian.org/debian' 'Suites: trixie-backports' 'Components: main' 'Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg' | sudo tee /etc/apt/sources.list.d/backports.sources
sudo apt update
```

Systems that still use `/etc/apt/sources.list` need a `deb-src` line for
each `deb` line there instead. Then install the build dependencies and build,
from a clone of this repository. On Debian 13 with backports:

```sh
sudo apt build-dep -t trixie-backports mesa
./scripts/build-debian-package.sh patches/mesa-26.1 trixie-backports
```

On Debian testing, `sudo apt build-dep mesa`, then
`./scripts/build-debian-package.sh patches/mesa-26.1`; on Debian unstable,
the same with `patches/mesa-26.2`.

The packages end up in `mesa-nvfix`, and the script ends with the
`sudo apt install` command for the ones the system has: run it. Their
version ends in `+nvfix1`. When Debian updates Mesa, apt replaces them with
Debian's own, without the patches: build again, with the folder for the new
version. The script builds for the system's own architecture only; Mesa's
packages for other architectures, such as the i386 ones Wine and Steam
install, must have the same version, so apt will want to remove those.

### Fedora

Fedora builds Mesa without the H.264 decoder, for patent reasons, so even
without the patches these GPUs only decode MPEG-2 there.
[`scripts/build-fedora-package.sh`](../scripts/build-fedora-package.sh)
rebuilds Fedora's own Mesa packages with the patches and with every decoder
(`-Dvideo-codecs=all`): it downloads Fedora's source package, adds the
patches to its spec file and builds every package. On a 4-core machine that
takes about 15 to 20 minutes, several times more on an older dual-core one.
The build dependencies and the packages take about 3 GB; while it builds,
the build tree needs several GB more, which rpmbuild removes at the end.

From a clone of this repository, on Fedora 44 or 45:

```sh
sudo dnf install rpm-build dnf-plugins-core
./scripts/build-fedora-package.sh patches/mesa-26.2
```

On Fedora 43, use `patches/mesa-26.0`. The script asks for sudo once, to
install the build dependencies of the source package it downloaded. The
packages end up in
`mesa-nvfix/rpmbuild/RPMS`, and the script ends with the `sudo dnf install`
command for the ones the system has: run it. Their release ends in
`.nvfix`, as in `26.2.6-1.fc44.nvfix`.

If RPM Fusion's `mesa-va-drivers-freeworld` is installed, remove it:
`sudo dnf remove mesa-va-drivers-freeworld`. libva loads that driver before
the system one, and it has no patches. When Fedora updates Mesa, dnf
replaces these packages with Fedora's own: build again, with the folder for
the new version. As on Debian, the script builds for the system's own
architecture only.

### Try it without installing

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

**From source, on any distribution.**
[`scripts/build-va-driver.sh`](../scripts/build-va-driver.sh) builds the VA
driver from a Mesa source tree and a folder of patches. Use the Mesa version
the system has and the folder that fits it, and Mesa's build dependencies
(on Debian and Ubuntu, `sudo apt build-dep mesa`; on Fedora,
`dnf download --source mesa`, then `sudo dnf builddep mesa-*.src.rpm`). For
Mesa 26.2.6:

```sh
git clone --depth 1 --branch mesa-26.2.6 https://gitlab.freedesktop.org/mesa/mesa.git mesa-26.2.6
./scripts/build-va-driver.sh mesa-26.2.6 patches/mesa-26.2 out
LIBVA_DRIVERS_PATH=$PWD/out LIBVA_DRIVER_NAME=nouveau vainfo
```

This driver supports Wayland and DRM displays, which is what Firefox and mpv
use on a Wayland desktop. X11 applications need a full Mesa build. 0004
fixes the OpenGL driver and 0011 the GBM import Chromium uses, which this VA
driver does not replace either; [`TESTING.md`](TESTING.md#7-uniform-buffer-updates-reach-their-buffer-0004)
shows how to try a full build for a single program.

Firefox reads VA drivers only from system directories inside its RDD sandbox.
To test a driver from another directory, also set `MOZ_DISABLE_RDD_SANDBOX=1`
for that run only. Installed packages put the driver in the system
directories, so Firefox needs neither variable.

## 2. Video firmware

nouveau needs firmware for the video decoder that only NVIDIA's own driver
contains, and NVIDIA's license does not allow anyone else to redistribute it.
[`scripts/install-firmware.sh`](../scripts/install-firmware.sh) downloads
NVIDIA's 340.108 driver from nvidia.com, checks it, extracts the firmware with
[envytools](https://github.com/envytools/firmware) and copies it to
`/lib/firmware/nouveau`:

```sh
./scripts/install-firmware.sh
```

Run it as your user: it asks for sudo only to copy the files. It needs
`python3` and `curl` or `wget`, and about 400 MB of temporary space. No reboot
is needed: the decoder loads the firmware the first time a program uses it.

## 3. Browsers

### Firefox

**Use Mozilla's .deb, not the Snap or Flatpak.** The Snap and Flatpak builds
bring their own Mesa and never use the system one. Ubuntu installs the Snap by
default; Zorin OS installs the .deb through its own Firefox installer. To
switch, follow Mozilla's
[instructions for Debian-based distributions](https://support.mozilla.org/kb/install-firefox-linux#w_install-firefox-deb-package-for-debian-based-distributions),
in short:

```sh
sudo install -d -m 0755 /etc/apt/keyrings
wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O- | sudo tee /etc/apt/keyrings/packages.mozilla.org.asc > /dev/null
gpg --show-keys /etc/apt/keyrings/packages.mozilla.org.asc
echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" | sudo tee /etc/apt/sources.list.d/mozilla.list > /dev/null
printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' | sudo tee /etc/apt/preferences.d/mozilla > /dev/null
sudo apt update
sudo apt install firefox
```

The fingerprint `gpg` prints must be
`35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3`. The .deb keeps its profile in
`~/.mozilla`, not in the Snap's directory: sign in to Firefox Sync, or copy
the profile over, to keep bookmarks and passwords.

**Allow hardware decoding.** Firefox blocks VA-API on every NVIDIA GPU unless
`media.hardware-video-decoding.force-enabled` is true.
[`scripts/setup-firefox.sh`](../scripts/setup-firefox.sh) sets it for every
profile through the system policy file
`/etc/firefox/policies/policies.json`, keeping any policies already there:

```sh
./scripts/setup-firefox.sh
```

Restart Firefox; `about:policies` lists the preference. To set it for one
profile only, set it to `true` in `about:config` instead.

### Brave and other Chromium browsers

Brave, like Chromium, blocks VA-API on NVIDIA GPUs and uses it on Linux only
when asked to. With these options Brave 1.97 (Chromium 155) decodes in
hardware on GNOME's Wayland desktop, local files and YouTube alike
(`brave://media-internals` shows `VaapiVideoDecoder`):

```
--ozone-platform=wayland --enable-features=AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL,VaapiOnNvidiaGPUs,VaapiIgnoreDriverChecks
```

Brave reads no options file, so put them in your own copies of its
launchers, which take precedence over the package's:

```sh
F='--ozone-platform=wayland --enable-features=AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL,VaapiOnNvidiaGPUs,VaapiIgnoreDriverChecks'
mkdir -p ~/.local/share/applications
for f in brave-browser.desktop com.brave.Browser.desktop; do
  sed "s#^Exec=/usr/bin/brave-browser-stable#& $F#" /usr/share/applications/$f > ~/.local/share/applications/$f
done
```

The options then apply to new windows, private windows and links opened from
other programs. Delete the two copies to undo. They do not follow changes to
the package's launchers: redo them if Brave changes its own.

Other Chromium-based browsers, such as Chromium, Google Chrome or Vivaldi,
use the same code and take the same options on their command line; this was
not tested.

These options were tested on a GT 240M under GNOME (Zorin OS 18). On a
Kepler GT 710 under KDE Plasma on Wayland, Brave's default OpenGL backend
showed no frames at all, with or without VA-API; this has not been tried on
KDE here. On Fermi and Kepler, Brave needs 0011: without it, its GPU process
restarts when it creates the frame buffers (`gbm_bo_import` fails in its
log) and playback falls back to software decoding. With it, Brave decodes in
hardware on a Kepler GK104 under GNOME.

### Sites that serve H.264

These GPUs decode H.264, MPEG-2 and VC-1 only. VP4 (GT21x) is designed for
H.264 High up to 1080p30 (level 4.1); 1080p60 is beyond it. YouTube serves
VP9 or AV1 by default: an extension such as enhanced-h264ify, for Firefox or
Chromium browsers, makes it serve H.264.

## 4. GPU clocks

nouveau never changes the GPU clocks on its own: the GPU stays at the
performance level the VBIOS picked at boot, often a middle one. At that level
the decoder may be slower than the CPU. List the levels, as root; the current
one is marked with `*`:

```sh
sudo cat /sys/kernel/debug/dri/*/pstate
```

Set the fastest level at boot with the `nouveau.config=NvClkMode` kernel
parameter, using the highest id from that list with `0x` in front. For a list
that ends in `0f`:

```sh
sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="/&nouveau.config=NvClkMode=0xf /' /etc/default/grub
sudo update-grub
```

On Fedora: `sudo grubby --update-kernel=ALL --args=nouveau.config=NvClkMode=0xf`.

The level applies from the next boot. It works on Tesla GPUs (GeForce 8 to
300) and most Kepler GPUs; Fermi (GeForce 400 and 500) cannot change clocks.

**Do not switch levels while the desktop runs.** Writing a level to the
`pstate` file works most of the time, but on a GeForce GT 240M lowering the
clocks while the screen was off and raising them when it came back broke the
GPU twice in about twenty tries: once it hung at once, once the desktop's drawing
failed every frame until the GPU hung. With the level fixed, twenty screen
wake-ups went clean. Set the level at boot and leave it.

## 5. Check that it works

```sh
sudo apt install vainfo
vainfo
```

On Fedora the package is `libva-utils`. `vainfo` lists H.264, MPEG-2 and VC-1
profiles with `VAEntrypointVLD`; without them, the firmware is missing.

In Firefox, open `about:support`: in the *Media* section, the codec support
table marks hardware decoding as supported for H264. On YouTube, *Stats for
nerds* shows an `avc1` codec. While a video plays, `top` shows Firefox well
below one full core. In Brave, open `brave://media-internals` while a video
plays: its player shows `VaapiVideoDecoder`.

For GTK 4, with the patched Mesa installed: remove `GSK_RENDERER=gl` if you
set it to work around garbled menus, and open a few menus in Files.
[`TESTING.md`](TESTING.md) has the detailed checks behind the results in the
README.
