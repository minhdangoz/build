#!/usr/bin/env bash
# Build TX68 Ubuntu and package it as a PhoenixSuit eMMC image.

set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
images_dir="${repo_root}/output/images"
phoenix_dir="${repo_root}/output/phoenix"
uboot_deb="${script_dir}/uboot-debs/linux-u-boot-next-tx68-fdtfix_0.1.0_arm64.deb"
boot_cmd="${script_dir}/bootscripts/boot-tx68-next.cmd"

newest_file() {
	local directory="$1"
	local pattern="$2"
	find "${directory}" -maxdepth 1 -type f -name "${pattern}" \
		-printf '%T@ %p\n' | sort -n | tail -n 1 | cut -d' ' -f2-
}

cd "${repo_root}"

[[ -f "${uboot_deb}" ]] || {
	echo "ERROR: signed TX68 U-Boot package is missing: ${uboot_deb}" >&2
	exit 1
}
[[ -f "${boot_cmd}" ]] || {
	echo "ERROR: TX68 boot script is missing: ${boot_cmd}" >&2
	exit 1
}

./compile.sh \
	BOARD=tx68 \
	BRANCH=current \
	RELEASE=noble \
	BUILD_DESKTOP=yes \
	DESKTOP_TIER=mid \
	DESKTOP_ENVIRONMENT=gnome \
	KERNEL_CONFIGURE=no

raw_image="$(newest_file "${images_dir}" 'Armbian-*Tx68_noble_current_*_gnome_desktop.img')"
[[ -n "${raw_image}" && -f "${raw_image}" ]] || {
	echo "ERROR: TX68 raw image was not produced" >&2
	exit 1
}
[[ -f "${raw_image}.sha" ]] || {
	echo "ERROR: raw-image SHA256 file is missing: ${raw_image}.sha" >&2
	exit 1
}

(
	cd "${images_dir}"
	sha256sum --check "$(basename "${raw_image}.sha")"
)

TX68_UBOOT_DEB="${uboot_deb}" \
	TX68_BOOT_CMD="${boot_cmd}" \
	bash "${script_dir}/scripts/tx68-build-phoenix-image.sh" "${raw_image}"

raw_stem="$(basename "${raw_image}" .img)"
phoenix_image="$(newest_file "${phoenix_dir}" "${raw_stem}_*_phoenixsuite.img")"
[[ -n "${phoenix_image}" && -f "${phoenix_image}" ]] || {
	echo "ERROR: TX68 PhoenixSuit image was not produced" >&2
	exit 1
}
[[ -f "${phoenix_image}.sha256" ]] || {
	echo "ERROR: PhoenixSuit SHA256 file is missing: ${phoenix_image}.sha256" >&2
	exit 1
}

(
	cd "${phoenix_dir}"
	sha256sum --check "$(basename "${phoenix_image}.sha256")"
)

printf '\nTX68 build completed successfully.\n'
printf 'Raw image:          %s\n' "${raw_image}"
printf 'PhoenixSuit image: %s\n' "${phoenix_image}"
printf 'Flash-tool input:  %s\n' "${phoenix_image}"
