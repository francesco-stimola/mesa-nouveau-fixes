#!/bin/sh
# Build only Mesa's VA driver for nouveau, with the patches of this
# repository applied, so that it can be tested through LIBVA_DRIVERS_PATH
# without touching the system Mesa.
#
# usage: build-va-driver.sh <mesa-source-dir> <patch-dir> <output-dir>
#
# The source directory is left untouched: it is copied to
# <output-dir>/src first. The driver ends up in
# <output-dir>/nouveau_drv_video.so.
#
# OpenGL is disabled, so Mesa links the VA frontend into a standalone
# libgallium_drv_video.so instead of the shared libgallium. Only the
# Wayland/DRM platforms are built: in this configuration the X11 one fails
# to link (missing xcb-xfixes).

set -eu

if [ $# -ne 3 ]; then
   echo "usage: $0 <mesa-source-dir> <patch-dir> <output-dir>" >&2
   exit 2
fi

src=$(realpath "$1")
patches=$(realpath "$2")
out=$(realpath -m "$3")

mkdir -p "$out"
rm -rf "$out/src" "$out/build"
cp -a "$src" "$out/src"
cd "$out/src"

for p in "$patches"/*.patch; do
   echo "Applying $(basename "$p")"
   patch -p1 --forward --no-backup-if-mismatch < "$p"
done

echo "$(cat VERSION)-nvfix" > VERSION

# Mesa 25.3 removed VDPAU.
vdpau=
if grep -q "'gallium-vdpau'" meson.options; then
   vdpau=-Dgallium-vdpau=disabled
fi

meson setup "$out/build" . \
   -Dbuildtype=release -Db_ndebug=true \
   -Dplatforms=wayland \
   -Dgallium-drivers=nouveau -Dvulkan-drivers=[] \
   -Dopengl=false -Dglx=disabled -Degl=disabled -Dgbm=disabled \
   -Dgles1=disabled -Dgles2=disabled \
   -Dgallium-va=enabled -Dvideo-codecs=all $vdpau \
   -Dllvm=disabled -Dvalgrind=disabled -Dlibunwind=disabled \
   -Dtools=[] -Dbuild-tests=false

ninja -C "$out/build"

cp "$out/build/src/gallium/targets/va/libgallium_drv_video.so" \
   "$out/nouveau_drv_video.so"
cd "$out"
sha256sum nouveau_drv_video.so
echo "Built $(cat src/VERSION): $out/nouveau_drv_video.so"
