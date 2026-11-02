#!/bin/sh
# Rebuild Debian's Mesa packages with the patches of this repository, to
# install them in place of Debian's own.
#
# usage: build-debian-package.sh <patch-dir> [<suite>]
#
# Run it as a normal user on the Debian release the packages are for, with
# deb-src entries enabled and Mesa's build dependencies installed
# (docs/SETUP.md). <suite> takes the source from that suite, such as
# trixie-backports; by default apt picks the newest one it knows.
#
# Everything happens in ./mesa-nvfix, which is emptied first. The packages
# end up there, and the script prints the command that installs the ones
# this system already has. Debian's tests and debug symbols are skipped.

set -eu

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
	echo "usage: $0 <patch-dir> [<suite>]" >&2
	exit 2
fi

patches=$(realpath "$1")
suite=${2:-}
out=$(realpath -m mesa-nvfix)

rm -rf "$out"
mkdir -p "$out"
cd "$out"

if [ -n "$suite" ]; then
	apt-get source -t "$suite" mesa
else
	apt-get source mesa
fi
cd mesa-*/

# dpkg-buildpackage applies every patch in debian/patches/series that is not
# applied yet, without fuzz.
for p in "$patches"/*.patch; do
	file=nvfix-$(basename "$p")
	cp "$p" "debian/patches/$file"
	echo "$file" >> debian/patches/series
done

version=$(dpkg-parsechangelog -S Version)+nvfix1
{
	printf 'mesa (%s) UNRELEASED; urgency=medium\n\n' "$version"
	printf '  * Patches from mesa-nouveau-fixes, %s.\n' "$(basename "$patches")"
	printf '\n -- %s  %s\n\n' "${DEBFULLNAME:-Local build} <${DEBEMAIL:-root@localhost}>" "$(date -R)"
	cat debian/changelog
} > debian/changelog.new
mv debian/changelog.new debian/changelog

DEB_BUILD_OPTIONS="nocheck noddebs parallel=$(nproc)" dpkg-buildpackage -b -uc -us

installed=
for deb in "$out"/*.deb; do
	pkg=$(dpkg-deb -f "$deb" Package)
	if dpkg-query -W -f '${Status}' "$pkg" 2> /dev/null | grep -q 'ok installed'; then
		installed="$installed $deb"
	fi
done
echo
echo "Built mesa $version in $out. To install the packages this system has:"
echo "sudo apt install$installed"
