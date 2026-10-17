#!/bin/sh
# Build Ubuntu's Mesa with the patches as a source package for the PPA,
# sign it and upload it, when there is something new to upload.
#
# Usage: ppa-upload.sh <series> <patch dir>
#
# Run it on the Ubuntu release it builds for (in CI, a container of that
# release), with deb-src entries enabled. Environment:
#   MODE        auto: upload when Ubuntu has a newer Mesa than the PPA
#               rebuild: also upload a new +nvfixN when the versions match
#   DRY_RUN     1: build and sign, but do not upload
#   PPA         Launchpad PPA (default ~francesco-stimola/mesa-nouveau-fixes)
#   SIGN_KEY    key to sign with; unset: leave the upload unsigned
#   GPG_PASSPHRASE_FILE  file with the key's passphrase
#   SOURCE_URL  link written in the changelog (default: this repository)
set -eu

series=$1
patches=$(cd "$2" && pwd)
mode=${MODE:-auto}
dry_run=${DRY_RUN:-0}
ppa=${PPA:-~francesco-stimola/mesa-nouveau-fixes}
owner=${ppa%%/*}
owner=${owner#\~}
name=${ppa#*/}
source_url=${SOURCE_URL:-https://github.com/francesco-stimola/mesa-nouveau-fixes}
maintainer="Francesco Stimola <francesco.stimola@proton.me>"
api=https://api.launchpad.net/devel

say() { echo "ppa-upload: $*"; }

# Newest mesa source version the enabled Ubuntu pockets offer.
ubuntu=
for v in $(apt-cache showsrc mesa | awk '/^Version:/ { print $2 }'); do
	if [ -z "$ubuntu" ] || dpkg --compare-versions "$v" gt "$ubuntu"; then
		ubuntu=$v
	fi
done
[ -n "$ubuntu" ] || { say "no mesa source in the apt sources"; exit 1; }

# Newest mesa version in the PPA for this series, pending or published.
current=$(curl -fsS "$api/~$owner/+archive/ubuntu/$name?ws.op=getPublishedSources&source_name=mesa&exact_match=true&order_by_date=true&distro_series=$api/ubuntu/$series" |
	jq -r '[.entries[] | select(.status == "Published" or .status == "Pending")][0].source_package_version // empty')

say "$series: Ubuntu has mesa $ubuntu, the PPA has ${current:-nothing}"
base=${current%+nvfix*}
rev=${current##*+nvfix}
if [ -z "$current" ] || dpkg --compare-versions "$ubuntu" gt "$base"; then
	version=$ubuntu+nvfix1
elif [ "$mode" = rebuild ] && [ "$ubuntu" = "$base" ]; then
	version=$ubuntu+nvfix$((rev + 1))
else
	say "nothing to upload"
	exit 0
fi
say "building $version"

work=$(mktemp -d)
cd "$work"
apt-get source --download-only "mesa=$ubuntu" > /dev/null 2>&1
dpkg-source -x mesa_*.dsc src > /dev/null
cd src

export QUILT_PATCHES=debian/patches
subjects=
for p in "$patches"/*.patch; do
	file=nvfix-$(basename "$p")
	cp "$p" "debian/patches/$file"
	echo "$file" >> debian/patches/series
	# The subject, joined across folded header lines, without [PATCH n/m].
	subject=$(awk '/^Subject: / { s = $0; f = 1; next } f && /^ / { s = s $0; next } f { exit } END { print s }' "$p" |
		sed -e 's/^Subject: *//' -e 's/^\[PATCH[^]]*\] *//' -e 's/  */ /g')
	subjects="$subjects$subject
"
done
quilt push -a > ../quilt.log 2>&1 || {
	cat ../quilt.log
	say "the patches in $patches do not apply to mesa $ubuntu"
	exit 1
}

commit=${GITHUB_SHA:-$(git -C "$patches" rev-parse HEAD 2> /dev/null || echo unknown)}
{
	printf 'mesa (%s) %s; urgency=medium\n\n' "$version" "$series"
	printf '  * Ubuntu mesa %s with the patches from\n' "$ubuntu"
	printf '    %s (%.12s):\n' "$source_url" "$commit"
	printf '%s' "$subjects" | while IFS= read -r s; do
		printf '%s\n' "$s" | fold -s -w 70 | sed -e '1s/^/    - /' -e '2,$s/^/      /'
	done
	printf '\n -- %s  %s\n\n' "$maintainer" "$(date -R)"
	cat debian/changelog
} > debian/changelog.new
mv debian/changelog.new debian/changelog
sed -n '1,/^ -- /p' debian/changelog

# The tree comes straight from apt-get source: no clean step, so the build
# dependencies are not needed. -sd: Launchpad already has Ubuntu's tarball.
dpkg-buildpackage -S -sd -d -nc -us -uc > ../source-build.log 2>&1 || {
	tail -30 ../source-build.log
	exit 1
}
cd ..
changes=mesa_${version}_source.changes

if [ -n "${SIGN_KEY:-}" ]; then
	cat > sign <<- EOF
		#!/bin/sh
		exec gpg --batch --pinentry-mode loopback --passphrase-file "$GPG_PASSPHRASE_FILE" "\$@"
	EOF
	chmod 700 sign
	debsign -k"$SIGN_KEY" -p"$work/sign" "$changes"
	rm -f sign
fi

if [ "$dry_run" = 1 ]; then
	say "dry run: not uploading $changes"
	ls -la "$work"/*.dsc "$work"/*.changes
else
	dput "ppa:$owner/$name" "$changes"
	say "uploaded $version for $series"
fi
