#!/bin/sh
# Check that a patch series applies to a Mesa source tree without fuzz, as
# dpkg-source and rpmbuild require when they rebuild a distribution's
# package. Line offsets are fine; changed context lines are not.
#
# usage: check-exact.sh <mesa-source-dir> <patch-dir>
#
# The source directory is left untouched: the patches go to a copy.

set -eu

if [ $# -ne 2 ]; then
   echo "usage: $0 <mesa-source-dir> <patch-dir>" >&2
   exit 2
fi

src=$(realpath "$1")
patches=$(realpath "$2")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cp -a "$src" "$tmp/src"
cd "$tmp/src"

for p in "$patches"/*.patch; do
   if ! patch -p1 --fuzz=0 --forward --no-backup-if-mismatch -s < "$p"; then
      echo "$(basename "$p") does not apply without fuzz" >&2
      exit 1
   fi
done
echo "Every patch in $patches applies without fuzz"
