#!/bin/sh
# Decode a clip through VA and save frames first..last (every step-th) as PNG.
# usage: grab.sh <driver dir|sw> <clip> <first> <last> <step> <out dir> [vf]
# The whole clip is decoded: a decode is never stopped half way.
drv=$1 clip=$2 first=$3 last=$4 step=$5 out=$6 vf=${7:-}
mkdir -p "$out"
rm -f "$out"/*.png
sel="select='between(n,$first,$last)*not(mod(n-$first,$step))'"
if [ "$drv" = sw ]; then
  ffmpeg -nostdin -v error -apply_cropping 0 -i "$clip" -vf "${vf:+$vf,}$sel" -fps_mode vfr "$out/%03d.png"
else
  LIBVA_DRIVERS_PATH=$drv ffmpeg -nostdin -v error -apply_cropping 0 -hwaccel vaapi -hwaccel_output_format vaapi -i "$clip" \
    -vf "${vf:-hwdownload,format=nv12},$sel" -fps_mode vfr "$out/%03d.png"
fi
ls "$out" | wc -l
