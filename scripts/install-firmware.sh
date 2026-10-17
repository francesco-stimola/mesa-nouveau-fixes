#!/bin/sh
# Install the video decoding firmware nouveau needs on GeForce 8 to 700
# GPUs. The firmware comes from NVIDIA's 340.108 driver, which this script
# downloads from nvidia.com, and is extracted with envytools'
# extract_firmware.py. Both downloads are checked against known checksums.
# Nothing from NVIDIA is stored in this repository.
#
# Usage: ./scripts/install-firmware.sh [destination]
#   destination  defaults to /lib/firmware/nouveau
#
# Run it as your user: it only uses sudo to copy the files when the
# destination is not writable. Set NVIDIA_RUN to the path of an already
# downloaded NVIDIA-Linux-x86_64-340.108.run to skip that download.
set -eu

dest=${1:-/lib/firmware/nouveau}

version=340.108
run=NVIDIA-Linux-x86_64-$version.run
run_url=https://us.download.nvidia.com/XFree86/Linux-x86_64/$version/$run
run_sha256=c671d4f1b7c09bc1af079b98b447adb06d704b04f802f7045a611fa50133b71b

tool_commit=a0b9f9be0efad90cc84b8b2eaf587c3d7d350ea9
tool_url=https://raw.githubusercontent.com/envytools/firmware/$tool_commit/extract_firmware.py
tool_sha256=b684b37b69a78f58fb3a6cf73684698a65927e701adedbae736ddbb0d1768ea7

die() {
	echo "install-firmware: $*" >&2
	exit 1
}

for cmd in python3 sha256sum; do
	command -v "$cmd" > /dev/null || die "$cmd is required"
done

download() {
	if command -v curl > /dev/null; then
		curl -fL --retry 3 --progress-bar -o "$2" "$1"
	elif command -v wget > /dev/null; then
		wget -O "$2" "$1"
	else
		die "curl or wget is required"
	fi
}

check() {
	echo "$2  $1" | sha256sum -c --quiet - || die "$1 does not match its expected checksum"
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"

echo "Downloading envytools' extract_firmware.py ($tool_commit)"
download "$tool_url" extract_firmware.py
check extract_firmware.py "$tool_sha256"

if [ -n "${NVIDIA_RUN:-}" ]; then
	cp "$NVIDIA_RUN" "$run"
else
	echo "Downloading $run from nvidia.com (67 MB)"
	download "$run_url" "$run"
fi
check "$run" "$run_sha256"

echo "Extracting the firmware"
sh "./$run" --extract-only > /dev/null
python3 extract_firmware.py > extract.log 2>&1 || {
	cat extract.log >&2
	die "extract_firmware.py failed"
}

# The firmware files are the lower-case nv* and vuc-* files, some of them
# symlinks between GPU names; the extracted driver is NVIDIA-Linux-*.
set -- nv* vuc-*
[ -e "$1" ] || die "no firmware files were extracted"

if mkdir -p "$dest" 2> /dev/null && [ -w "$dest" ]; then
	cp -d "$@" "$dest/"
else
	echo "Copying to $dest needs root"
	sudo mkdir -p "$dest"
	sudo cp -d "$@" "$dest/"
fi
echo "Installed $# firmware files in $dest"
