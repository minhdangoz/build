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
# Bifrost binding that the in-tree Panfrost driver matches. Live KM7 hardware
# identifies as Mali-G31 (GPU ID 0x7093); Mesa renders through Panfrost and
# devfreq exposes the complete 285.714-846 MHz OPP range.
DEFAULT_OVERLAYS="panfrost"

# KM7 is mains-powered. Amlogic's four S905Y4 silicon-bin OPP tables all top
# out at 2004 MHz and the S4 clock driver carries the matching PLL rate.
# 2208 MHz is not a vendor OPP and remains unsupported.
CPUMIN="500000"
CPUMAX="2004000"
GOVERNOR="performance"

# TV-box images should reach the desktop without requiring a keyboard during
# first boot. Account/locale values still come from userpatches/firstboot.conf.
declare -g DESKTOP_AUTOLOGIN="yes"
declare -g CONSOLE_AUTOLOGIN="yes"
PACKAGE_LIST_BOARD="net-tools"

enable_extension "wayland-sessions-mask"
enable_extension "km7-amlogic-burn"

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

function post_family_tweaks__km7_firstboot_identity() {
	# userpatches/firstboot.conf is global and can contain presets intended for
	# another board. Account identity is a board invariant, so make the KM7
	# values authoritative in the image while preserving locale/network knobs.
	declare firstboot_file="${SDCARD}/root/.not_logged_in_yet"
	touch "${firstboot_file}"
	sed -i \
		-e '/^PRESET_USER_NAME=/d' \
		-e '/^PRESET_USER_PASSWORD=/d' \
		-e '/^PRESET_DEFAULT_REALNAME=/d' \
		-e '/^PRESET_ROOT_PASSWORD=/d' \
		"${firstboot_file}"
	cat <<- 'KM7_FIRSTBOOT_IDENTITY' >> "${firstboot_file}"

		# KM7 board-owned first-login identity
		PRESET_USER_NAME="km7"
		PRESET_USER_PASSWORD="km7"
		PRESET_DEFAULT_REALNAME="KM7"
		PRESET_ROOT_PASSWORD="km7"
	KM7_FIRSTBOOT_IDENTITY
}

# Front-panel FD650 (Amlogic's LED-class driver in the aggregate
# amlogic-led.ko module -- /sys/class/leds/fd650/*, not the out-of-tree
# chardev driver TX68 uses). fd650ctl and the rotation script are shared,
# board-detecting code in packages/bsp/common/ (see docs/FD650.md and
# config/boards/tx68.conf's matching install block) -- only the
# device-specific glue below (udev rule, systemd unit device path) is
# KM7-specific. There is no automatic packages/bsp/<family>/<board>/ ->
# rootfs mirroring in this framework (checked lib/functions/ directly --
# the only two consumers of packages/bsp/common/ are the separate
# armbian-bsp-cli .deb artifact and one explicit `cp` in
# distro-agnostic.sh), so every file below needs its own explicit install
# line, same as TX68's board hook.
function post_family_tweaks__km7_enable_front_panel() {
	run_host_command_logged install -m 755 "${SRC}/packages/bsp/common/usr/local/bin/fd650ctl" "${SDCARD}/usr/local/bin/fd650ctl"
	run_host_command_logged install -m 755 "${SRC}/packages/bsp/common/usr/local/bin/fd650-clock-rotate" "${SDCARD}/usr/local/bin/fd650-clock-rotate"

	# MODE=/GROUP= on a udev rule line only affects a /dev node, which this
	# LED-class device doesn't have (pure sysfs, no /dev node) -- confirmed
	# on real hardware that MODE=/GROUP= alone leaves the sysfs attributes
	# root:root 0644. RUN+= chmod/chgrp the actual attribute files instead.
	# TAG+="systemd" makes systemd generate a device unit so the service
	# below can be device-activated instead of waiting for
	# systemd-udev-settle.
	run_host_command_logged install -m 644 "${SRC}/packages/bsp/meson-s4t7/km7/99-fd650-km7.rules" "${SDCARD}/etc/udev/rules.d/99-fd650-km7.rules"

	# Same polkit grant as TX68 (see tx68.conf), shared file: both boards'
	# unit names are whitelisted in it so "video" group members can
	# fd650ctl daemon start/stop/restart without sudo.
	run_host_command_logged install -m 644 "${SRC}/packages/bsp/common/49-fd650-clock.rules" "${SDCARD}/etc/polkit-1/rules.d/49-fd650-clock.rules"

	run_host_command_logged install -m 644 "${SRC}/packages/bsp/meson-s4t7/km7/etc/systemd/system/km7-fd650-clock.service" "${SDCARD}/lib/systemd/system/km7-fd650-clock.service"
	chroot_sdcard systemctl --no-reload enable km7-fd650-clock.service
}

# Remote desktop: TV-box use case has no keyboard/mouse attached (see
# DESKTOP_AUTOLOGIN above), so GUI access has to come over the network.
# x11vnc mirrors the real X11 session (wayland-sessions-mask above already
# forces GDM onto Xorg) rather than starting a second display. Shared with
# TX68 -- same unit file, same port 5900, same storepasswd mechanism (see
# config/boards/tx68.conf's matching block).
function post_family_tweaks__km7_remote_desktop() {
	chroot_sdcard_apt_get_install openssh-server x11vnc

	# Password lives in /etc/x11vnc.pass, matching the km7/km7 console
	# account's own security posture (LAN-only box, see
	# post_family_tweaks__km7_firstboot_identity above) -- change both after
	# first boot if this device is ever exposed beyond a trusted LAN.
	chroot_sdcard "x11vnc -storepasswd km7 /etc/x11vnc.pass"
	run_host_command_logged install -m 644 "${SRC}/packages/bsp/common/lib/systemd/system/x11vnc.service" "${SDCARD}/lib/systemd/system/x11vnc.service"
	chroot_sdcard systemctl --no-reload enable x11vnc.service ssh.service
}
