# Mecool KM7 TV box: Amlogic S905Y4/S4 (AP222), 4GB DDR3, eMMC, 100M Ethernet,
# Amlogic W1 WiFi/BT and FD650 front-panel display. Same SoC as Khadas VIM1S,
# but not the same board wiring or DRAM/boot firmware.
BOARD_NAME="Mecool KM7"
BOARD_VENDOR="mecool"
BOARDFAMILY="meson-s4t7"
BOARD_MAINTAINER=""
# The inspected unit's PCB revision is dated 2024-04-28. No earlier product
# date is asserted here without a primary source.
INTRODUCED="2024"
KERNEL_TARGET="legacy"
KERNEL_TEST_TARGET="legacy"
SERIALCON="ttyS0:921600"

BOOTCONFIG="km7_defconfig"
KHADAS_BOARD_ID="km7"
BOOT_FDT_FILE="amlogic/km7.dtb"
BOOT_LOGO="desktop"
FORCE_BOOTSCRIPT_UPDATE="yes"

OVERLAY_PREFIX="s4-s905y4"
# This overlay replaces the vendor Midgard-compatible GPU binding with the
# Bifrost binding that the in-tree Panfrost driver matches. GPU acceleration
# still requires proof from the renderer on real KM7 hardware.
DEFAULT_OVERLAYS="panfrost"

# KM7 is mains-powered and Fenix used this range/governor. 1704 MHz is the
# highest OPP actually present in meson-s4.dtsi; do not inherit Fenix's stale
# 2208 MHz clamp, which names a frequency the S905Y4 table does not provide.
CPUMIN="500000"
CPUMAX="1704000"
GOVERNOR="conservative"

# TV-box images should reach the desktop without requiring a keyboard during
# first boot. Account/locale values still come from userpatches/firstboot.conf.
declare -g DESKTOP_AUTOLOGIN="yes"
declare -g CONSOLE_AUTOLOGIN="yes"
PACKAGE_LIST_BOARD="net-tools"

enable_extension "wayland-sessions-mask"

# Family configuration is sourced after this file, so append board-only patch
# sets here. The common-drivers patches use paths prefixed with common_drivers/
# because Armbian copies that Khadas tree into the Linux worktree before its
# normal patch stage.
function post_family_config__km7_patchsets_and_bootargs() {
	declare -g KERNELPATCHDIR="${KERNELPATCHDIR} archive/meson-s4t7-5.15-km7"
	declare -g BOOTPATCHDIR="${BOOTPATCHDIR} u-boot-meson-s4t7-km7"
}

# Armbian owns the final kernel .config, not common_drivers/kvims_defconfig.
# Request the two KM7-only symbols through the config hook as well as carrying
# their upstream defconfig patch for source-tree completeness.
function custom_kernel_config__km7_drivers() {
	opts_m+=("AMLOGIC_W1")
	opts_y+=("AMLOGIC_LEDS_FD650")
}

function pre_build_uboot_fip__km7_bl30_ir_api() {
	# AP222's BL30 source still calls the six-argument vIRInit API, while the
	# current Khadas/CoreELEC BL30 bundle exposes the same five-argument API used
	# by VIM1S. The source is fetched/materialized outside the U-Boot git tree,
	# so a normal U-Boot patch cannot own this compatibility fix.
	declare bl30_power="${PWD}/bl30/src_ao/demos/amlogic/n200/s4/s4_ap222/power.c"
	if grep -q 'vIRInit(MODE_HARD_NEC, GPIOD_5' "${bl30_power}"; then
		sed -i \
			's/vIRInit(MODE_HARD_NEC, GPIOD_5/vIRInit(GPIOD_5/' \
			"${bl30_power}"
	elif ! grep -q 'vIRInit(GPIOD_5' "${bl30_power}"; then
		exit_with_error "KM7 BL30 vIRInit API is not recognized" "${bl30_power}"
	fi
}

function km7_bsp_legacy_postinst_link_video_firmware() {
	ln -sf video_ucode.bin.s4 /lib/firmware/video/video_ucode.bin
}

function post_family_tweaks_bsp__km7_link_video_firmware_on_install() {
	postinst_functions+=(km7_bsp_legacy_postinst_link_video_firmware)
}

function post_family_tweaks_bsp__km7_module_lists() {
	# KM7 and VIM1S share the S4 provider/media module graph. Reuse that list
	# from one maintained place, then replace only the board-specific radio.
	run_host_command_logged cp -R \
		"${SRC}/packages/bsp/meson-s4t7/khadas-vim1s/etc/initramfs-tools" \
		"${destination}/etc/"
	run_host_command_logged cp -R \
		"${SRC}/packages/bsp/meson-s4t7/khadas-vim1s/etc/modprobe.d" \
		"${destination}/etc/"
	run_host_command_logged cp \
		"${SRC}/packages/bsp/meson-s4t7/khadas-vim1s/etc/modules" \
		"${destination}/etc/modules"

	# Broadcom dhd cannot bind the live-verified 0x8888:0x8888 W1 device.
	# aml_sdio is the transport and must load before vlsicomm.
	run_host_command_logged sed -i '/^dhd$/d' "${destination}/etc/modules"
	run_host_command_logged rm -f "${destination}/etc/modprobe.d/dhd.conf"
	cat <<- 'KM7_W1_MODULES' >> "${destination}/etc/modules"

		# Mecool KM7 Amlogic W1 SDIO radio
		aml_sdio
		vlsicomm
	KM7_W1_MODULES
}

function image_specific_armbian_env_ready__km7_kernel_args() {
	# The vendor kernel has kvm-arm.mode=protected built into CONFIG_CMDLINE,
	# which is not usable with KM7's secure firmware. A later argument wins.
	run_host_command_logged echo "extraargs=kvm-arm.mode=none" ">>" "${SDCARD}/boot/armbianEnv.txt"
}

function post_family_tweaks__km7_enable_front_panel() {
	chroot_sdcard systemctl --no-reload enable km7-fd650-clock.service
}
