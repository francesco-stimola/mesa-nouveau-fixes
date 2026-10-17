#!/bin/sh
# Decode FFmpeg's copy of the H.264 conformance streams in software and on the
# GPU through VA-API, and count for each stream the frames whose MD5 differs
# from software decoding. H.264 decoding is exact, so a correct decoder
# differs on no frame.
#
# usage: h264-conformance.sh <work-dir> [<VA driver dir>...]
#
# The streams are downloaded into <work-dir> on the first run. Each VA driver
# directory gets a column; "system", the default, is the VA driver installed
# on the system. "-" means the GPU did not decode the stream, for example
# because it uses a profile the decoder lacks.
#
# Every GPU decode runs alone and to the end of the stream: on nouveau,
# a decoder stopped half way can leave the video engine hung.

set -u

base=https://fate-suite.ffmpeg.org/h264-conformance

if [ $# -lt 1 ]; then
	echo "usage: $0 <work-dir> [<VA driver dir>...]" >&2
	exit 2
fi
work=$1
shift
[ $# -gt 0 ] || set -- system
drivers=
for d in "$@"; do
	[ "$d" = system ] || d=$(realpath "$d")
	drivers="$drivers $d"
done

mkdir -p "$work"
cd "$work" || exit 1

if [ ! -s streams.txt ]; then
	{
		curl -fsSL "$base/" | grep -o 'href="[^"?/][^"]*"' | cut -d'"' -f2
		curl -fsSL "$base/FRext/" | grep -o 'href="[^"?/][^"]*"' | cut -d'"' -f2 | sed 's|^|FRext/|'
	} | grep -v -E 'md5sum|Hi422|PPH10|PPH422|/$' > streams.txt
fi

md5s() {
	grep -v '^#' | awk -F, '{ print NR, $6 }'
}

gpu() {
	if [ "$2" = system ]; then
		ffmpeg -nostdin -v error -f h264 -hwaccel vaapi -hwaccel_output_format vaapi -i "$1" \
			-an -vf hwdownload,format=nv12 -f framemd5 - 2> /dev/null
	else
		LIBVA_DRIVERS_PATH=$2 ffmpeg -nostdin -v error -f h264 -hwaccel vaapi -hwaccel_output_format vaapi \
			-i "$1" -an -vf hwdownload,format=nv12 -f framemd5 - 2> /dev/null
	fi
}

printf '%-30s %6s %5s %8s' stream frames coded temporal
for d in $drivers; do
	printf ' %8.8s' "$(basename "$d")"
done
echo

while read -r f; do
	name=$(echo "$f" | tr / _)
	[ -s "$name" ] || curl -fsSL -o "$name" "$base/$f" || continue

	# Interlaced coding and B slices with temporal direct prediction.
	trace=$(ffmpeg -nostdin -v info -f h264 -i "$name" -c copy -bsf:v trace_headers -f null - 2>&1)
	coded=frame
	echo "$trace" | grep -q 'frame_mbs_only_flag .* = 1$' || coded=field
	temporal=$(echo "$trace" | grep -c 'direct_spatial_mv_pred_flag .* = 0$')

	ffmpeg -nostdin -v error -f h264 -i "$name" -an -pix_fmt nv12 -f framemd5 - 2> /dev/null | md5s > "$name.cpu"
	printf '%-30s %6s %5s %8s' "$name" "$(wc -l < "$name.cpu")" "$coded" "$temporal"
	for d in $drivers; do
		gpu "$name" "$d" | md5s > "$name.gpu"
		if [ -s "$name.gpu" ]; then
			printf ' %8s' "$(diff "$name.cpu" "$name.gpu" | grep -c '^<')"
		else
			printf ' %8s' -
		fi
	done
	echo
done < streams.txt
