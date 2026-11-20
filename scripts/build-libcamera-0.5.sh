#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Cross-build libcamera for the tablet and write an installable tarball.
#
# The distro (trixie) ships libcamera 0.4, whose simple IPA has no Ccm
# algorithm, so the colour tuning files cannot be used and the desktop camera
# apps show uncalibrated colours.  This builds 0.5.x (with the GStreamer
# plugin, so GNOME Snapshot's libcamerasrc picks it up) into out/.
#
# Usage:
#   ./scripts/build-libcamera-0.5.sh [VERSION]
#
# Environment:
#   NABU_BUILDER_IMAGE   builder image tag (default nabu-main-builder:<arch>)
#   OUT                  output directory (default ./out)

set -eu

VERSION=${1:-${LIBCAMERA_VERSION:-0.5.2}}
here=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$here/out}

case "$(uname -m)" in
x86_64 | amd64) arch=amd64 ;;
aarch64 | arm64) arch=arm64 ;;
*)
	echo "unsupported host architecture: $(uname -m)" >&2
	exit 1
	;;
esac
BUILDER=${NABU_BUILDER_IMAGE:-nabu-main-builder:$arch}

# The builder image is the same one nabu-main uses for the kernel/userspace
# builds; see nabu-main/docker/build-image.sh.
if ! docker image inspect "$BUILDER" >/dev/null 2>&1; then
	echo "error: builder image $BUILDER not found" >&2
	echo "       build it with nabu-main/docker/build-image.sh" >&2
	exit 1
fi

src=$(mktemp -d)
trap 'rm -rf "$src"' EXIT
mkdir -p "$OUT"

echo "== fetching libcamera v$VERSION"
# Use a local cached tarball when present (fetches can get truncated).
cache="$here/out/libcamera-$VERSION.tar.gz"
if [ -s "$cache" ] && gzip -t "$cache" 2>/dev/null; then
	tar -xzf "$cache" -C "$src" --strip-components=1
else
	curl -fsSL "https://github.com/libcamera-org/libcamera/archive/refs/tags/v$VERSION.tar.gz" -o "$cache" ||
	curl -fsSL "https://github.com/libcamera-org/libcamera/archive/refs/tags/$VERSION.tar.gz" -o "$cache"
	gzip -t "$cache" || { rm -f "$cache"; echo "error: truncated download" >&2; exit 1; }
	tar -xzf "$cache" -C "$src" --strip-components=1
fi

# Apply the nabu patches (lens plumbing + contrast autofocus for the simple
# pipeline) on top of the pristine release.
for patch_file in "$here"/patches/libcamera-*.patch; do
	[ -e "$patch_file" ] || continue
	echo "== applying $(basename "$patch_file")"
	(cd "$src" && patch -p1 --forward < "$patch_file")
done

cat > "$src/cross.txt" <<'CROSS'
[binaries]
c = 'aarch64-linux-gnu-gcc'
cpp = 'aarch64-linux-gnu-g++'
ar = 'aarch64-linux-gnu-ar'
strip = 'aarch64-linux-gnu-strip'
pkg-config = 'pkg-config'

[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'

[properties]
pkg_config_libdir = '/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig'
CROSS

echo "== building in $BUILDER"
docker run --rm -v "$src:/src:ro" -v "$OUT:/out" -e VERSION="$VERSION" \
	"$BUILDER" bash -c '
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
	g++-aarch64-linux-gnu libyaml-dev:arm64 libevent-dev:arm64 \
	libssl-dev:arm64 libgstreamer1.0-dev:arm64 \
	libgstreamer-plugins-base1.0-dev:arm64 python3-jinja2 python3-yaml \
	python3-ply pkg-config >/dev/null 2>&1

cp -a /src /tmp/src
cd /tmp/src

meson setup build --cross-file /tmp/src/cross.txt --prefix=/usr/local \
	--libdir=lib/aarch64-linux-gnu --buildtype=release \
	-Dpipelines=simple -Dipas=simple -Dcam=enabled -Dgstreamer=enabled \
	-Dpycamera=disabled -Dtest=false -Ddocumentation=disabled \
	-Dtracing=disabled >/tmp/meson.log 2>&1 || { tail -n 20 /tmp/meson.log; exit 1; }
ninja -C build >/tmp/ninja.log 2>&1 || { tail -n 20 /tmp/ninja.log; exit 1; }
DESTDIR=/tmp/stage ninja -C build install >/dev/null
tar -C /tmp/stage/usr/local -czf "/out/libcamera-$VERSION-arm64.tar.gz" .
'

echo "== wrote $OUT/libcamera-$VERSION-arm64.tar.gz"
echo "   install with: sudo ./scripts/install-libcamera-0.5.sh $OUT/libcamera-$VERSION-arm64.tar.gz"
