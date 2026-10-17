#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# nabu-shot - take a still with a nabu camera through libcamera.
#
# GNOME Snapshot goes through xdg-desktop-portal -> PipeWire, and that path
# currently hangs in GStreamer (see KNOWN-ISSUES 2.4.9).  Until that is fixed
# upstream, this talks to libcamera directly and stitches the frames into an
# image with ffmpeg.
#
# usage: nabu-shot [-c camera] [-w width] [-H height] [-n frames] out.png
#
#   -c  camera index as listed by "cam -l"    (default 1, the front camera)
#   -w  capture width                          (default 1640)
#   -H  capture height                         (default 1232)
#   -n  frames to capture                      (default 25)
#
# The last frame is the one that is written: AGC needs about 10 frames to
# converge and AWB about 25, so the first frames are dark and green.

set -eu

camera=1
width=1640
height=1232
frames=25

usage() {
	echo "usage: $0 [-c camera] [-w width] [-H height] [-n frames] out.png" >&2
	exit 1
}

while getopts "c:w:H:n:" opt; do
	case "$opt" in
	c) camera=$OPTARG ;;
	w) width=$OPTARG ;;
	H) height=$OPTARG ;;
	n) frames=$OPTARG ;;
	*) usage ;;
	esac
done
shift $((OPTIND - 1))
[ $# -eq 1 ] || usage
out=$1

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# cam writes every frame back to back into one file, as ABGR8888 (ffmpeg's
# "bgra"); the simple IPA's software ISP only produces that format.
cam -c "$camera" --capture="$frames" --file="$tmp/frames" \
	-s "width=$width,height=$height"

frame_bytes=$((width * height * 4))
tail -c "$frame_bytes" "$tmp/frames" > "$tmp/last.bgra"

ffmpeg -hide_banner -loglevel error -y \
	-f rawvideo -pix_fmt bgra -s "${width}x${height}" \
	-i "$tmp/last.bgra" "$out"

echo "wrote $out ($width x $height)"
