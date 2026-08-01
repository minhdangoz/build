#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Convert the normal Armbian raw KM7 image into the S4/AP222 upgrade-package
# format consumed by Amlogic USB Burning Tool. The raw image remains available
# for SD-card testing; the additional .emmc.img is the destructive eMMC path.

declare -g KM7_BURN_TMPDIR=""

function cleanup_km7_burn_tmpdir() {
	[[ -n "${KM7_BURN_TMPDIR}" && -d "${KM7_BURN_TMPDIR}" ]] || return 0
	find "${KM7_BURN_TMPDIR}" -type l -delete
	find "${KM7_BURN_TMPDIR}" -type f -delete
	find "${KM7_BURN_TMPDIR}" -depth -type d -empty -delete
}

function km7_burn_fetch_tools() {
	local -r images_upgrade_ref="commit:80d7e303878e13f01b955c630861fbbbae94e304"
	local -r utils_ref="commit:0b209089f98929267fce98dcd7d34672cb5b98fc"

	fetch_from_repo \
		"https://github.com/minhdangoz/images_upgrade.git" \
		"km7-images-upgrade" \
		"${images_upgrade_ref}"
	fetch_from_repo \
		"https://github.com/minhdangoz/utils.git" \
		"km7-fenix-utils" \
		"${utils_ref}"
}

function post_build_image__910_km7_amlogic_burn() {
	[[ "${BOARD}" == "km7" ]] || return 0
	: "${version:?version is not set}"

	local -r raw_image="${DESTIMG}/${version}.img"
	local -r burn_image="${DESTIMG}/${version}.emmc.img"
	local -r images_upgrade_dir="${SRC}/cache/sources/km7-images-upgrade/Amlogic"
	local -r packer="${SRC}/cache/sources/km7-fenix-utils/aml_image_v2_packer"

	[[ -f "${raw_image}" ]] || exit_with_error "KM7 raw image not found" "${raw_image}"
	km7_burn_fetch_tools
	[[ -x "${packer}" ]] || exit_with_error "KM7 Amlogic image packer not found" "${packer}"

	KM7_BURN_TMPDIR="$(mktemp -d)"
	local -r tmpdir="${KM7_BURN_TMPDIR}"
	add_cleanup_handler cleanup_km7_burn_tmpdir

	local uboot_deb dtb_deb
	# Extension methods execute in a generated wrapper where Armbian's artifact
	# map is not preserved reliably. Select the newest matching package by mtime;
	# unlike lexical hash sorting this chooses the artifact just used above.
	uboot_deb="$(find "${DEB_STORAGE}" -maxdepth 1 -type f \
		-name 'linux-u-boot-km7-legacy_*.deb' -printf '%T@ %p\n' | \
		sort -n | tail -n 1 | cut -d' ' -f2-)"
	dtb_deb="$(find "${DEB_STORAGE}" -maxdepth 1 -type f \
		-name 'linux-dtb-legacy-meson-s4t7_*.deb' -printf '%T@ %p\n' | \
		sort -n | tail -n 1 | cut -d' ' -f2-)"
	[[ -n "${uboot_deb}" ]] || exit_with_error "KM7 U-Boot package not found"
	[[ -n "${dtb_deb}" ]] || exit_with_error "KM7 DTB package not found"

	mkdir -p "${tmpdir}/uboot" "${tmpdir}/dtb"
	dpkg-deb -x "${uboot_deb}" "${tmpdir}/uboot"
	dpkg-deb -x "${dtb_deb}" "${tmpdir}/dtb"

	local name source_file
	for name in u-boot.bin.sd.bin.signed u-boot.bin.signed u-boot.bin.usb.signed; do
		source_file="$(find "${tmpdir}/uboot/usr/lib" -type f -name "${name}" -print -quit)"
		[[ -n "${source_file}" ]] || exit_with_error "KM7 U-Boot package lacks ${name}" "${uboot_deb}"
		cp "${source_file}" "${tmpdir}/${name}"
	done

	source_file="$(find "${tmpdir}/dtb/boot" -type f -path '*/amlogic/km7.dtb' -print -quit)"
	[[ -n "${source_file}" ]] || exit_with_error "KM7 DTB missing from package" "${dtb_deb}"
	cp "${source_file}" "${tmpdir}/kvim.dtb"

	cp "${images_upgrade_dir}/package_s4.conf" "${tmpdir}/package.conf"
	cp "${images_upgrade_dir}/platform_s4.conf" "${tmpdir}/platform.conf"
	cp "${images_upgrade_dir}/aml_sdc_burn.ini" "${tmpdir}/aml_sdc_burn.ini"
	cp "${images_upgrade_dir}/usb_flow.aml" "${tmpdir}/usb_flow.aml"

	local partition_line start_sector sector_count
	partition_line="$(sfdisk -d "${raw_image}" 2>/dev/null | grep 'start=' || true)"
	[[ "$(wc -l <<< "${partition_line}")" -eq 1 ]] || \
		exit_with_error "KM7 burn packer expects exactly one raw-image partition"
	start_sector="$(sed 's/.*start= *\([0-9]*\).*/\1/' <<< "${partition_line}")"
	sector_count="$(sed 's/.*size= *\([0-9]*\).*/\1/' <<< "${partition_line}")"
	[[ "${start_sector}" =~ ^[0-9]+$ && "${sector_count}" =~ ^[0-9]+$ ]] || \
		exit_with_error "Could not parse KM7 rootfs partition geometry"

	display_alert "KM7" "Extracting ext4 rootfs for Amlogic package" "info"
	run_host_command_logged dd if="${raw_image}" of="${tmpdir}/rootfs.img" \
		bs=512 skip="${start_sector}" count="${sector_count}" conv=sparse status=progress

	display_alert "KM7" "Packing S4/AP222 USB Burning Tool image" "info"
	run_host_x86_binary_logged "${packer}" -r "${tmpdir}/package.conf" "${tmpdir}" "${burn_image}"
	[[ -f "${burn_image}" ]] || exit_with_error "KM7 EMMC burn image was not produced"

	# Amlogic v2 header: CRC32 at offset 0 (changes per image), version at
	# offset 4, and the fixed AML_RES_IMG_V1_MAGIC at offset 8.
	local version_word magic
	version_word="$(od -An -tu4 -j4 -N4 "${burn_image}" | tr -d ' ')"
	magic="$(od -An -tx4 -j8 -N4 "${burn_image}" | tr -d ' ')"
	[[ "${version_word}" == "2" && "${magic}" == "27b51956" ]] || \
		exit_with_error "KM7 burn image has invalid Amlogic v2 header" "version=${version_word} magic=${magic}"
	display_alert "KM7" "Amlogic EMMC image ready: $(basename "${burn_image}")" "ok"

	execute_and_remove_cleanup_handler cleanup_km7_burn_tmpdir
}
