#!/usr/bin/env bash
# Build the proven KM7 Ubuntu image and its Amlogic USB Burning Tool package.

set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
images_dir="${repo_root}/output/images"

cd "${repo_root}"

./compile.sh \
	BOARD=km7 \
	BRANCH=legacy \
	RELEASE=noble \
	BUILD_DESKTOP=yes \
	DESKTOP_TIER=mid \
	DESKTOP_ENVIRONMENT=xfce \
	KERNEL_CONFIGURE=no

newest_image() {
	local pattern="$1"
	find "${images_dir}" -maxdepth 1 -type f -name "${pattern}" \
		-printf '%T@ %p\n' | sort -n | tail -n 1 | cut -d' ' -f2-
}

raw_image="$(newest_image 'Armbian-*Km7_noble_legacy_*_xfce_desktop.img')"
emmc_image="$(newest_image 'Armbian-*Km7_noble_legacy_*_xfce_desktop.emmc.img')"

[[ -n "${raw_image}" && -f "${raw_image}" ]] || {
	echo "ERROR: KM7 raw image was not produced" >&2
	exit 1
}
[[ -n "${emmc_image}" && -f "${emmc_image}" ]] || {
	echo "ERROR: KM7 Amlogic eMMC image was not produced" >&2
	exit 1
}
[[ -f "${raw_image}.sha" && -f "${emmc_image}.sha" ]] || {
	echo "ERROR: image SHA256 file is missing" >&2
	exit 1
}

(
	cd "${images_dir}"
	sha256sum --check "$(basename "${raw_image}.sha")"
	sha256sum --check "$(basename "${emmc_image}.sha")"
)

printf '\nKM7 build completed successfully.\n'
printf 'Raw SD image:       %s\n' "${raw_image}"
printf 'Amlogic eMMC image: %s\n' "${emmc_image}"
printf 'Burn Tool input:    %s\n' "${emmc_image}"
