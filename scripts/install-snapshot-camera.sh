#!/usr/bin/env bash
# Build and install the nabu-patched GNOME Snapshot 50.0 for the current user.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname -- "${SCRIPT_DIR}")"
PATCH_PATH="${REPO_DIR}/camera-app/gnome-snapshot-50.0-nabu.patch"
INSTALL_PREFIX="${SNAPSHOT_INSTALL_PREFIX:-${HOME}/.local}"

usage() {
	cat <<EOF
Usage: $0

Builds GNOME Snapshot 50.0 with the nabu orientation and high-resolution
still-capture fixes, runs its test suite, and installs it under:
  ${INSTALL_PREFIX}

Override the destination with SNAPSHOT_INSTALL_PREFIX. Do not run with sudo.
EOF
}

if [[ ${1:-} == "--help" || ${1:-} == "-h" ]]; then
	usage
	exit 0
fi

if [[ $# -ne 0 ]]; then
	usage >&2
	exit 2
fi

if [[ ${EUID} -eq 0 ]]; then
	echo "Error: run this installer as the desktop user, without sudo." >&2
	exit 1
fi

if [[ ! -s ${PATCH_PATH} ]]; then
	echo "Error: patch not found: ${PATCH_PATH}" >&2
	exit 1
fi

for command_name in git meson ninja cargo; do
	if ! command -v "${command_name}" >/dev/null 2>&1; then
		echo "Error: required command not found: ${command_name}" >&2
		exit 1
	fi
done

WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/nabu-snapshot.XXXXXX")"
SOURCE_DIR="${WORK_ROOT}/snapshot"
BUILD_DIR="${WORK_ROOT}/build"

cleanup() {
	case ${WORK_ROOT} in
		"${TMPDIR:-/tmp}"/nabu-snapshot.*) rm -rf -- "${WORK_ROOT}" ;;
		*) echo "Warning: refusing to remove unexpected path: ${WORK_ROOT}" >&2 ;;
	esac
}
trap cleanup EXIT

echo "Downloading GNOME Snapshot 50.0..."
git clone --quiet --depth 1 --branch 50.0 \
	https://github.com/GNOME/snapshot.git "${SOURCE_DIR}"

git -C "${SOURCE_DIR}" apply --check "${PATCH_PATH}"
git -C "${SOURCE_DIR}" apply "${PATCH_PATH}"

meson setup "${BUILD_DIR}" "${SOURCE_DIR}" \
	--buildtype=release \
	--prefix="${INSTALL_PREFIX}"
ninja -C "${BUILD_DIR}"
meson test -C "${BUILD_DIR}" cargo-test --print-errorlogs
meson install -C "${BUILD_DIR}"

echo
echo "Patched Snapshot installed successfully:"
echo "  ${INSTALL_PREFIX}/bin/snapshot"
echo "Restart Camera if it is already running."
