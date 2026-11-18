#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Install the libcamera 0.5 tree built by build-libcamera-0.5.sh into
# /usr/local and make the GStreamer plugin the one desktop apps load.
#
# The distro libcamera 0.4 stays untouched: everything here lives under
# /usr/local and is selected by GST_PLUGIN_PATH, so a rollback is just
# --rollback.
#
# Usage:
#   sudo ./scripts/install-libcamera-0.5.sh out/libcamera-0.5.2-arm64.tar.gz
#   sudo ./scripts/install-libcamera-0.5.sh --rollback

set -eu

prefix=/usr/local
libdir=$prefix/lib/aarch64-linux-gnu
gstdir=$libdir/gstreamer-1.0
ldconf=/etc/ld.so.conf.d/nabu-libcamera.conf
envconf=/etc/environment.d/50-nabu-gst.conf
gstpath=$gstdir

rollback()
{
	rm -f "$ldconf" "$envconf" \
		"$libdir"/libcamera.so* "$libdir"/libcamera-base.so* \
		"$gstdir"/libgstlibcamera.so \
		"$prefix"/bin/cam
	# Drop the GST_PLUGIN_PATH line we added to /etc/environment.
	if [ -f /etc/environment ] &&
	   grep -q "^GST_PLUGIN_PATH=$gstpath$" /etc/environment; then
		sed -i "\|^GST_PLUGIN_PATH=$gstpath\$|d" /etc/environment
	fi
	rm -rf "$prefix/share/libcamera"
	ldconfig
	echo "libcamera 0.5 removed from $prefix; the distro 0.4 is active again"
}

if [ "${1:-}" = "--rollback" ]; then
	rollback
	exit 0
fi

if [ $# -ne 1 ]; then
	echo "usage: $0 <libcamera-0.5-*.tar.gz> | --rollback" >&2
	exit 1
fi
tarball=$1
[ -f "$tarball" ] || { echo "error: $tarball not found" >&2; exit 1; }

echo "== installing into $prefix"
mkdir -p "$prefix"
tar -C "$prefix" -xzf "$tarball"

echo "== making libcamera.so.0.5 resolvable"
echo "$libdir" > "$ldconf"
ldconfig

echo "== pointing GStreamer at the 0.5 plugin"
mkdir -p /etc/environment.d
echo "GST_PLUGIN_PATH=$gstpath" > "$envconf"
if [ -f /etc/environment ] &&
   ! grep -q "^GST_PLUGIN_PATH=$gstpath$" /etc/environment; then
	echo "GST_PLUGIN_PATH=$gstpath" >> /etc/environment
fi

# Tuning files are version-gated: a Ccm profile makes a 0.4 IPA fail hard.
if [ -d "$prefix/share/libcamera/ipa/simple" ]; then
	echo "== tuning files present in $prefix/share/libcamera/ipa/simple"
fi

echo
echo "Verify (a new login session is needed for desktop apps):"
echo "  gst-inspect-1.0 libcamerasrc | grep -E 'Filename|Version'"
echo "  GST_PLUGIN_PATH=$gstpath gst-inspect-1.0 libcamerasrc | grep Version"
echo "  systemctl --user show-environment | grep GST_PLUGIN_PATH"
