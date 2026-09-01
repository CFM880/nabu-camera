#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname -- "${SCRIPT_DIR}")"
BUILD_DIR="${BUILD_DIR:-${REPO_DIR}/out}"
KERNEL_RELEASE="$(uname -r)"
INSTALL_DIR="/lib/modules/${KERNEL_RELEASE}/updates/nabu-camera"
TUNING_DIR="/usr/share/libcamera/ipa/simple"

CCI_SOURCE="${BUILD_DIR}/drivers/i2c/busses/i2c-qcom-cci.ko"
CAMSS_SOURCE="${BUILD_DIR}/drivers/media/platform/qcom/camss/qcom-camss.ko"
CN3927_SOURCE="${BUILD_DIR}/drivers/media/i2c/cn3927.ko"
OV13B10_TUNING_SOURCE="${REPO_DIR}/camera-tuning/ov13b10.yaml"
OV8856_TUNING_SOURCE="${REPO_DIR}/camera-tuning/ov8856.yaml"

CCI_TARGET="${INSTALL_DIR}/i2c-qcom-cci.ko"
CAMSS_TARGET="${INSTALL_DIR}/qcom-camss.ko"
CN3927_TARGET="${INSTALL_DIR}/cn3927.ko"
OV13B10_TUNING_TARGET="${TUNING_DIR}/ov13b10.yaml"
OV8856_TUNING_TARGET="${TUNING_DIR}/ov8856.yaml"

usage() {
	cat <<EOF
Usage:
  sudo $0              Install the rebuilt camera modules and tuning profiles
  sudo $0 --rollback   Restore the previous overrides, or remove them

Set BUILD_DIR when the kernel was built out of tree, for example:
  sudo BUILD_DIR=/path/to/kernel/output $0
EOF
}

check_tuning() {
	local tuning_path=$1

	if [[ ! -s ${tuning_path} ]]; then
		echo "Error: camera tuning profile not found: ${tuning_path}" >&2
		exit 1
	fi

	if ! grep -q '^version: 1$' "${tuning_path}" ||
	   ! grep -q '^algorithms:$' "${tuning_path}"; then
		echo "Error: invalid camera tuning profile: ${tuning_path}" >&2
		exit 1
	fi
}

require_root() {
	if [[ ${EUID} -ne 0 ]]; then
		echo "Error: run this script with sudo." >&2
		echo "  sudo $0${1:+ $1}" >&2
		exit 1
	fi
}

check_module() {
	local module_path=$1
	local module_name=$2
	local vermagic

	if [[ ! -f ${module_path} ]]; then
		echo "Error: rebuilt module not found: ${module_path}" >&2
		exit 1
	fi

	vermagic="$(modinfo -F vermagic "${module_path}")"
	if [[ ${vermagic%% *} != "${KERNEL_RELEASE}" ]]; then
		echo "Error: ${module_name} was built for '${vermagic%% *}'," >&2
		echo "       but the running kernel is '${KERNEL_RELEASE}'." >&2
		exit 1
	fi
}

prepare_target() {
	local target=$1

	if [[ -e ${target}.managed ]]; then
		return
	fi

	if [[ -f ${target} && ! -f ${target}.bak ]]; then
		cp --preserve=mode,timestamps -- "${target}" "${target}.bak"
		echo "Backed up: ${target}.bak"
	fi
}

install_modules() {
	check_module "${CCI_SOURCE}" i2c_qcom_cci
	check_module "${CAMSS_SOURCE}" qcom_camss
	check_module "${CN3927_SOURCE}" cn3927
	check_tuning "${OV13B10_TUNING_SOURCE}"
	check_tuning "${OV8856_TUNING_SOURCE}"

	install -d -m 0755 -- "${INSTALL_DIR}"
	install -d -m 0755 -- "${TUNING_DIR}"
	prepare_target "${CCI_TARGET}"
	prepare_target "${CAMSS_TARGET}"
	prepare_target "${CN3927_TARGET}"
	prepare_target "${OV13B10_TUNING_TARGET}"
	prepare_target "${OV8856_TUNING_TARGET}"

	install -m 0644 -- "${CCI_SOURCE}" "${CCI_TARGET}"
	touch -- "${CCI_TARGET}.managed"
	install -m 0644 -- "${CAMSS_SOURCE}" "${CAMSS_TARGET}"
	touch -- "${CAMSS_TARGET}.managed"
	install -m 0644 -- "${CN3927_SOURCE}" "${CN3927_TARGET}"
	touch -- "${CN3927_TARGET}.managed"
	install -m 0644 -- "${OV13B10_TUNING_SOURCE}" "${OV13B10_TUNING_TARGET}"
	touch -- "${OV13B10_TUNING_TARGET}.managed"
	install -m 0644 -- "${OV8856_TUNING_SOURCE}" "${OV8856_TUNING_TARGET}"
	touch -- "${OV8856_TUNING_TARGET}.managed"
	depmod -a "${KERNEL_RELEASE}"

	if [[ $(modinfo -n i2c_qcom_cci) != "${CCI_TARGET}" ]]; then
		echo "Error: depmod did not select ${CCI_TARGET}." >&2
		exit 1
	fi

	if [[ $(modinfo -n qcom_camss) != "${CAMSS_TARGET}" ]]; then
		echo "Error: depmod did not select ${CAMSS_TARGET}." >&2
		exit 1
	fi

	if [[ $(modinfo -n cn3927) != "${CN3927_TARGET}" ]]; then
		echo "Error: depmod did not select ${CN3927_TARGET}." >&2
		exit 1
	fi

	echo
	echo "Camera modules installed successfully for ${KERNEL_RELEASE}:"
	echo "  ${CCI_TARGET}"
	echo "  ${CAMSS_TARGET}"
	echo "  ${CN3927_TARGET}"
	echo "  ${OV13B10_TUNING_TARGET}"
	echo "  ${OV8856_TUNING_TARGET}"
	echo
	echo "The old modules are still loaded in the running kernel. Reboot to apply:"
	echo "  sudo reboot"
}

restore_or_remove() {
	local target=$1

	if [[ ! -e ${target}.managed ]]; then
		echo "Not managed by this script: ${target}"
		return
	fi

	if [[ -f ${target}.bak ]]; then
		mv -f -- "${target}.bak" "${target}"
		echo "Restored: ${target}"
	elif [[ -f ${target} ]]; then
		rm -f -- "${target}"
		echo "Removed: ${target}"
	else
		echo "Already absent: ${target}"
	fi

	rm -f -- "${target}.managed"
}

rollback_modules() {
	restore_or_remove "${CCI_TARGET}"
	restore_or_remove "${CAMSS_TARGET}"
	restore_or_remove "${CN3927_TARGET}"
	restore_or_remove "${OV13B10_TUNING_TARGET}"
	restore_or_remove "${OV8856_TUNING_TARGET}"
	depmod -a "${KERNEL_RELEASE}"

	echo
	echo "Rollback prepared. Reboot to load the original modules:"
	echo "  sudo reboot"
}

case ${1:-} in
	"")
		require_root ""
		install_modules
		;;
	--rollback)
		require_root --rollback
		rollback_modules
		;;
	-h|--help)
		usage
		;;
	*)
		usage >&2
		exit 2
		;;
esac
