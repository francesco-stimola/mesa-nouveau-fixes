# Setup

What a GeForce 8 to 700 GPU on nouveau needs for hardware video decoding in
Firefox and Brave and a glitch-free GTK 4 desktop, on Ubuntu 24.04 or 26.04
and distributions based on them (Zorin OS 18, Linux Mint 22, ...), Wayland
session.

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

To try hardware decoding without installing anything, see
[Try it without installing](../README.md#try-it-without-installing).

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
hardware on a Wayland desktop, local files and YouTube alike
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

`vainfo` lists H.264, MPEG-2 and VC-1 profiles with `VAEntrypointVLD`; without
them, the firmware is missing.

In Firefox, open `about:support`: in the *Media* section, the codec support
table marks hardware decoding as supported for H264. On YouTube, *Stats for
nerds* shows an `avc1` codec. While a video plays, `top` shows Firefox well
below one full core. In Brave, open `brave://media-internals` while a video
plays: its player shows `VaapiVideoDecoder`.

For GTK 4, with the patched Mesa installed: remove `GSK_RENDERER=gl` if you
set it to work around garbled menus, and open a few menus in Files.
[`TESTING.md`](TESTING.md) has the detailed checks behind the results in the
README.
