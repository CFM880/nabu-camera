#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
set -eu

if [ "$#" -ne 2 ]; then
	echo "usage: $0 /path/to/linux /path/to/output" >&2
	exit 2
fi

kernel_tree=$(CDPATH= cd -- "$1" && pwd)
mkdir -p "$2"
output_dir=$(CDPATH= cd -- "$2" && pwd)

if [ ! -f "$kernel_tree/Makefile" ]; then
	echo "not a Linux source tree: $kernel_tree" >&2
	exit 1
fi

camera_dts=$kernel_tree/arch/arm64/boot/dts/qcom/sm8150-xiaomi-nabu-camera.dts
if [ ! -f "$camera_dts" ]; then
	echo "camera overlay is not installed; run scripts/apply-overlay.sh first" >&2
	exit 1
fi

if [ ! -f "$output_dir/.config" ]; then
	echo "missing configured kernel output: $output_dir/.config" >&2
	exit 1
fi

: "${ARCH:=arm64}"
: "${CROSS_COMPILE:=aarch64-linux-gnu-}"
: "${JOBS:=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
export ARCH CROSS_COMPILE

make -C "$kernel_tree" O="$output_dir" olddefconfig
make -C "$kernel_tree" O="$output_dir" -j"$JOBS" \
	modules qcom/sm8150-xiaomi-nabu-camera.dtb

dtb=$output_dir/arch/arm64/boot/dts/qcom/sm8150-xiaomi-nabu-camera.dtb
test -f "$dtb"
echo "built camera modules and $dtb"
