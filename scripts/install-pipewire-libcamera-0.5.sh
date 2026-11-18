#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Install the PipeWire SPA libcamera plugin built against libcamera 0.5
# (build-pipewire-libcamera-0.5.sh), so applications that take frames through
# PipeWire (GNOME Snapshot) get the calibrated colours and the built-in
# autofocus instead of the distro libcamera 0.4.
#
# The distro file is kept as a .nabu-orig backup; --rollback restores it.
#
# Usage:
#   sudo ./scripts/install-pipewire-libcamera-0.5.sh <libspa-libcamera-0.5-arm64.so>
#   sudo ./scripts/install-pipewire-libcamera-0.5.sh --rollback

set -eu

plugin=/usr/lib/aarch64-linux-gnu/spa-0.2/libcamera/libspa-libcamera.so
backup=${plugin}.nabu-orig

restart_services()
{
	for uid in $(loginctl list-users --no-legend 2>/dev/null | awk '{print $1}'); do
		[ "${uid:-0}" -ge 1000 ] || continue
		user=$(getent passwd "$uid" | cut -d: -f1)
		runuser -u "$user" -- env XDG_RUNTIME_DIR=/run/user/$uid \
			DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus \
			systemctl --user restart pipewire wireplumber 2>/dev/null || true
		echo "restarted pipewire/wireplumber for $user"
	done
}

if [ "$(id -u)" -ne 0 ]; then
	echo "Error: run this script with sudo." >&2
	exit 1
fi

if [ "${1:-}" = "--rollback" ]; then
	if [ -f "$backup" ]; then
		mv -f -- "$backup" "$plugin"
		echo "restored $plugin"
	else
		echo "Error: no backup found.  Restore the package instead:" >&2
		echo "  apt-get install --reinstall libspa-0.2-libcamera" >&2
		exit 1
	fi
	restart_services
	echo "Camera applications are back on the distro libcamera 0.4."
	exit 0
fi

if [ $# -ne 1 ]; then
	echo "usage: $0 <libspa-libcamera-0.5-arm64.so> | --rollback" >&2
	exit 1
fi
new_plugin=$1
[ -f "$new_plugin" ] || { echo "error: $new_plugin not found" >&2; exit 1; }

# libcamera.so.0.5 must be resolvable; install-libcamera-0.5.sh sets this up.
if ! ldconfig -p | grep -q "libcamera.so.0.5"; then
	echo "error: the libcamera 0.5 stack is not installed" >&2
	echo "       run ./scripts/install-libcamera-0.5.sh first" >&2
	exit 1
fi

if [ ! -f "$backup" ] && [ -f "$plugin" ]; then
	cp --preserve=mode,timestamps -- "$plugin" "$backup"
	echo "backed up $backup"
fi

install -m 0644 -- "$new_plugin" "$plugin"
echo "installed $plugin"

restart_services

echo
echo "Verify:"
echo "  pw-cli e \$(pw-dump | grep -m1 -B5 libcamera_input | ...) EnumFormat"
echo "  gst-launch-1.0 pipewiresrc target-object=<camera node name> ! fakesink"
echo "  watch focus_absolute move: v4l2-ctl -d <lens subdev> --get-ctrl focus_absolute"
echo "Restart the camera application to pick the new node up."
