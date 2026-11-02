#!/bin/sh
# Rebuild Fedora's Mesa packages with the patches of this repository and
# with every video decoder, to install them in place of Fedora's own.
#
# usage: build-fedora-package.sh <patch-dir>
#
# Run it as a normal user on the Fedora release the packages are for, with
# rpm-build and dnf-plugins-core installed (docs/SETUP.md). It asks for sudo
# once, to install the build dependencies of the source package it
# downloads. Fedora builds Mesa without the H.264, H.265 and VC-1 decoders;
# this rebuild turns them on (-Dvideo-codecs=all), as Debian and Ubuntu do.
#
# Everything happens in ./mesa-nvfix, which is emptied first. The packages
# end up in mesa-nvfix/rpmbuild/RPMS, and the script prints the command that
# installs the ones this system already has. Mesa's tests and debug
# packages are skipped.

set -eu

if [ $# -ne 1 ]; then
	echo "usage: $0 <patch-dir>" >&2
	exit 2
fi

patches=$(realpath "$1")
out=$(realpath -m mesa-nvfix)
top=$out/rpmbuild

rm -rf "$out"
mkdir -p "$out"
cd "$out"

dnf download --source mesa
rpm -i --define "_topdir $top" mesa-*.src.rpm
spec=$top/SPECS/mesa.spec

# %autosetup applies the patches in number order, so ours come after
# Fedora's own.
n=1000
add=
for p in "$patches"/*.patch; do
	n=$((n + 1))
	file=nvfix-$(basename "$p")
	cp "$p" "$top/SOURCES/$file"
	add="${add}Patch$n: $file
"
done

# The video decoders: set -Dvideo-codecs=all, or add it after -Dgallium-va.
has=0
if grep -q -- '-Dvideo-codecs=' "$spec"; then
	has=1
fi
awk -v add="$add" -v has="$has" '
	/^Source0:/ && !src { print; printf "%s", add; src = 1; next }
	has && /-Dvideo-codecs=/ { sub(/-Dvideo-codecs=[^ ]*/, "-Dvideo-codecs=all") }
	{ print }
	!has && /-Dgallium-va=/ { print "  -Dvideo-codecs=all \\" }
' "$spec" > "$spec.new"
mv "$spec.new" "$spec"
grep -q -- '-Dvideo-codecs=all' "$spec" || { echo "could not turn the video decoders on in $spec" >&2; exit 1; }

# The dependencies of this very spec: those of the mesa name may come from
# another version of the source package.
sudo=
if [ "$(id -u)" -ne 0 ]; then
	sudo=sudo
fi
$sudo dnf builddep -y "$spec"

# The spec generates more build dependencies, the Rust crates, in
# %generate_buildrequires: rpmbuild -br writes them into a source package
# and exits with 11 until they are installed.
dist=$(rpm -E %dist).nvfix
tries=0
while :; do
	rc=0
	rpmbuild -br --define "_topdir $top" --define "dist $dist" "$spec" > /dev/null || rc=$?
	if [ "$rc" -eq 0 ]; then
		break
	fi
	tries=$((tries + 1))
	if [ "$rc" -ne 11 ] || [ "$tries" -gt 5 ]; then
		echo "rpmbuild -br failed with $rc" >&2
		exit 1
	fi
	$sudo dnf builddep -y "$top"/SRPMS/*.buildreqs.nosrc.rpm
	rm -f "$top"/SRPMS/*.buildreqs.nosrc.rpm
done

rpmbuild -bb --nocheck --define "_topdir $top" --define "dist $dist" \
	--define "debug_package %{nil}" "$spec"

installed=
for rpm in "$top"/RPMS/*/*.rpm; do
	version=$(rpm -qp --qf '%{VERSION}-%{RELEASE}' "$rpm")
	if rpm -q "$(rpm -qp --qf '%{NAME}' "$rpm")" > /dev/null 2>&1; then
		installed="$installed $rpm"
	fi
done
echo
echo "Built mesa $version in $top/RPMS. To install the packages this system has:"
echo "sudo dnf install$installed"
