#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Cross-build PipeWire's SPA libcamera plugin against the libcamera 0.5
# stack built by build-libcamera-0.5.sh, and write the plugin to out/.
#
# The distro plugin is linked against libcamera 0.4, which has no Ccm
# algorithm, so every camera application that goes through PipeWire (GNOME
# Snapshot) shows uncalibrated colours and gets no autofocus.  This rebuilds
# just that plugin (same PipeWire version as the image ships) against 0.5.
#
# Usage:
#   ./scripts/build-pipewire-libcamera-0.5.sh [PIPEWIRE_VERSION]
#
# Requires: out/libcamera-0.5.*-arm64.tar.gz from build-libcamera-0.5.sh.
#
# Environment:
#   NABU_BUILDER_IMAGE   builder image tag (default nabu-main-builder:<arch>)
#   OUT                  output directory (default ./out)

set -eu

VERSION=${1:-1.4.2}
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

if ! docker image inspect "$BUILDER" >/dev/null 2>&1; then
	echo "error: builder image $BUILDER not found" >&2
	echo "       build it with nabu-main/docker/build-image.sh" >&2
	exit 1
fi

lc_tarball=$(ls -1 "$OUT"/libcamera-0.5.*-arm64.tar.gz 2>/dev/null | sort -V | tail -n 1)
if [ -z "$lc_tarball" ]; then
	echo "error: no libcamera 0.5 tarball in $OUT" >&2
	echo "       run ./scripts/build-libcamera-0.5.sh first" >&2
	exit 1
fi
lc_version=${lc_tarball##*/libcamera-}
lc_version=${lc_version%%-arm64*}

src=$(mktemp -d)
stage=$(mktemp -d)
trap 'rm -rf "$src" "$stage" 2>/dev/null || true' EXIT
mkdir -p "$OUT"

echo "== fetching pipewire v$VERSION"
curl -fsSL "https://github.com/PipeWire/pipewire/archive/refs/tags/v$VERSION.tar.gz" |
	tar -xz -C "$src" --strip-components=1 || {
	curl -fsSL "https://github.com/PipeWire/pipewire/archive/refs/tags/$VERSION.tar.gz" |
		tar -xz -C "$src" --strip-components=1
}

echo "== staging libcamera $lc_version"
tar -C "$stage" -xzf "$lc_tarball"

cat > "$src/../pw-cross.txt" <<'CROSS'
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
pkg_config_libdir = '/usr/local/lib/aarch64-linux-gnu/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig'
CROSS

# Apply the nabu patches on top of the pristine release.
for patch_file in "$here"/patches/pipewire-*.patch; do
	[ -e "$patch_file" ] || continue
	echo "== applying $(basename "$patch_file")"
	(cd "$src" && patch -p1 --forward < "$patch_file")
done

echo "== building the plugin in $BUILDER"
docker run --rm -v "$src:/src:ro" -v "$stage:/lcstage:ro" \
	-v "$(dirname "$src")/pw-cross.txt:/cross.txt:ro" -v "$OUT:/out" \
	"$BUILDER" bash -c '
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq g++-aarch64-linux-gnu pkg-config libssl-dev:arm64 >/dev/null 2>&1

# Make the staged 0.5 stack visible to the cross pkg-config.
cp -a /lcstage/. /usr/local/
export PKG_CONFIG_LIBDIR=/usr/local/lib/aarch64-linux-gnu/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig

cp -a /src /tmp/src
cd /tmp/src
meson setup build --cross-file /cross.txt --buildtype=release \
	-Dlibcamera=enabled -Dspa-plugins=enabled \
	-Ddbus=disabled -Dudev=disabled -Dsystemd=disabled \
	-Dpipewire-alsa=disabled -Dpipewire-jack=disabled -Dgstreamer=disabled \
	-Dbluez5=disabled -Dvulkan=disabled -Dffmpeg=disabled -Draop=disabled \
	-Dtests=disabled -Dexamples=disabled -Ddocs=disabled -Dman=disabled \
	-Dsession-managers=[] >/tmp/meson.log 2>&1 || { tail -n 20 /tmp/meson.log; exit 1; }
ninja -C build spa/plugins/libcamera/libspa-libcamera.so >/tmp/ninja.log 2>&1 || { tail -n 25 /tmp/ninja.log; exit 1; }
cp build/spa/plugins/libcamera/libspa-libcamera.so /out/libspa-libcamera-0.5-arm64.so
readelf -d /out/libspa-libcamera-0.5-arm64.so | grep -E "NEEDED.*libcamera"
echo BUILD_OK
'

echo "== wrote $OUT/libspa-libcamera-0.5-arm64.so"
echo "   install with: sudo ./scripts/install-pipewire-libcamera-0.5.sh $OUT/libspa-libcamera-0.5-arm64.so"
