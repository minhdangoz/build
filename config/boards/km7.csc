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

source "${SRC}/config/boards/tx68-km7-source-lock.inc"

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
	declare -g KERNELSOURCE="${KM7_KERNEL_SOURCE}"
	declare -g KERNELBRANCH="${KM7_KERNEL_REF}"
	declare -g COMMON_DRIVERS_SOURCE="${KM7_COMMON_DRIVERS_SOURCE}"
	declare -g COMMON_DRIVERS_BRANCH="${KM7_COMMON_DRIVERS_REF}"
	declare -g BOOTSOURCE="${KM7_UBOOT_SOURCE}"
	declare -g BOOTBRANCH="${KM7_UBOOT_REF}"
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

# W1 Bluetooth requires Amlogic's vendor firmware transaction before it will
# answer normal HCI commands. The generic Ubuntu hciattach creates hci0 but
# receives no bytes. Keep the Android/Bionic dependencies private under
# /usr/lib/aml-bt; they were live-verified on this exact KM7 hardware.
function post_family_tweaks__km7_bluetooth() {
	chroot_sdcard_apt_get_install bluez rfkill
	run_host_command_logged install -d "${SDCARD}/usr/lib/aml-bt"
	run_host_command_logged cp -a "${SRC}/packages/bsp/meson-s4t7/km7/usr/lib/aml-bt/." "${SDCARD}/usr/lib/aml-bt/"
	run_host_command_logged install -m 644 "${SRC}/packages/bsp/meson-s4t7/km7/etc/systemd/system/km7-bluetooth.service" "${SDCARD}/lib/systemd/system/km7-bluetooth.service"
	chroot_sdcard systemctl --no-reload enable km7-bluetooth.service
}

function image_specific_armbian_env_ready__km7_kernel_args() {
	# The vendor kernel has kvm-arm.mode=protected built into CONFIG_CMDLINE,
	# which is not usable with KM7's secure firmware. A later argument wins.
	#
	# HDMI: also pin the boot display to 1080p60hz/RGB 8bit instead of letting
	# U-Boot's EDID auto-negotiation hand the kernel 2160p60hz + YCbCr420
	# 10bit. GNOME/mutter on this monitor fails to build a linear monitor
	# config ("No available CRTC for monitor 'unknown unknown'") and falls
	# back to requesting 1080p60hz, but it keeps the inherited 420,10bit
	# color format. meson_hdmitx_encoder_atomic_check rejects that specific
	# combo ("validate_mode fail for [1080p60hz-420,10bit]"), the atomic
	# commit never completes, and every later modeset attempt fails the same
	# way -- the display never recovers without a reboot. Live-verified on
	# real hardware (2026-08-02): forcing vout/hdmitx/hdmimode/hdmichecksum
	# here removes the EDID auto-negotiated 420,10bit start state and the
	# validate_mode failures stop appearing. A later "vout=" and "hdmitx="
	# token on the cmdline wins over U-Boot's own, same as kvm-arm.mode above.
	run_host_command_logged echo "extraargs=kvm-arm.mode=none vout=1080p60hz,enable hdmitx=,444,8bit hdmimode=1080p60hz hdmichecksum=0x00000000" ">>" "${SDCARD}/boot/armbianEnv.txt"
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

	# Live-confirmed trap (2026-08-02): /usr/lib/armbian/armbian-firstlogin's
	# gdm3 branch only makes AutomaticLoginEnable permanent if
	# /root/.desktop_autologin exists *before* the wizard's gdm3 branch runs;
	# otherwise it starts a background `sleep 20` that flips
	# AutomaticLoginEnable back to false. On a TV box nobody is at the
	# console within that 20s window, so every fresh flash silently loses
	# autologin and x11vnc's `-display :0 -auth
	# /run/user/1000/gdm/Xauthority` then fails outright (no X session ever
	# starts -- GDM sits at the greeter as user "gdm", not "km7"). Same
	# mechanism TX68 uses (see tx68.conf's post_family_tweaks__tx68): write
	# custom.conf directly and pre-drop the marker so the wizard's own write
	# is a no-op regardless of console interaction timing.
	mkdir -p "${SDCARD}"/etc/gdm3
	cat <<- 'KM7_GDM_AUTOLOGIN' > "${SDCARD}"/etc/gdm3/custom.conf
		[daemon]
		WaylandEnable=false
		AutomaticLoginEnable=true
		AutomaticLogin=km7
	KM7_GDM_AUTOLOGIN
	touch "${SDCARD}"/root/.desktop_autologin
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

# Noble's mid-tier GNOME selection installs gnome-shell's
# org.gnome.ScreenSaver activation script but not the /usr/bin/gjs interpreter
# named by that script.  gsd-usb-protection then crashes while constructing its
# screen-saver proxy and systemd/apport restart it indefinitely.  Make the
# runtime dependency part of every KM7 GNOME image; masking USB protection would
# only hide the packaging bug.
function post_family_tweaks__km7_gnome_runtime() {
	if [[ "${DESKTOP_ENVIRONMENT}" == "gnome" ]]; then
		chroot_sdcard_apt_get_install gjs
	fi
}

# Disable GNOME lockscreen by default (TV box with no keyboard can't unlock it).
# Matches TX68's behavior -- see tx68.conf post_family_tweaks__tx68().
function post_family_tweaks__km7_disable_lockscreen() {
	if [[ -d "${SDCARD}/etc/gdm3" || "${DESKTOP_ENVIRONMENT}" == "gnome" ]]; then
		mkdir -p "${SDCARD}"/etc/dconf/db/local.d
		cat <<- 'DCONF_NOLOCK' > "${SDCARD}"/etc/dconf/db/local.d/02-km7-no-lock
			[org/gnome/desktop/session]
			idle-delay=uint32 0

			[org/gnome/desktop/screensaver]
			idle-activation-enabled=false
			lock-enabled=false

			[org/gnome/desktop/lockdown]
			disable-lock-screen=true

			[org/gnome/settings-daemon/plugins/power]
			sleep-inactive-ac-timeout=0
			sleep-inactive-ac-type='nothing'
			sleep-inactive-battery-timeout=0
			sleep-inactive-battery-type='nothing'
			idle-dim=false

			[org/gnome/desktop/interface]
			color-scheme='prefer-dark'
			gtk-theme='Adwaita-dark'
		DCONF_NOLOCK
		chroot_sdcard "dconf update"
	fi
}

# KM7's Mali-G31 is the same weak GPU as TX68's, and panels attached to this
# box commonly report 4K as their native/preferred EDID mode, which is too
# slow to compose smoothly here -- and confirmed live on TX68, letting Xorg's
# own screen init pick a 4K initial mode can outright crash it
# ("AddScreen/ScreenInit failed for driver 0"), crash-looping GDM forever.
# Unlike TX68, nothing forces a mode at the U-Boot/kernel layer for KM7 (the
# vendor U-Boot's outputmode=none fallback to 1080p60hz only fires when
# EDID/HPD read fails entirely -- see
# patch/u-boot/u-boot-meson-s4t7-km7/0002-km7-fall-back-to-1080p60hz...patch),
# so this needs the same X11-layer fix TX68 uses: the shared xorg.conf.d
# monitor override makes Xorg's own initial mode selection match against the
# connector's real EDID-probed mode list (the working CEA timing) instead of
# defaulting to native 4K. The xrandr autostart script stays too, as a
# harmless no-op safety net for whatever this ends up matching to.
function post_family_tweaks__km7_force_1080p() {
	mkdir -p "${SDCARD}"/etc/X11/xorg.conf.d
	run_host_command_logged install -m 644 "${SRC}/packages/bsp/common/etc/X11/xorg.conf.d/10-monitor.conf" "${SDCARD}/etc/X11/xorg.conf.d/10-monitor.conf"

	run_host_command_logged install -m 755 "${SRC}/packages/bsp/common/usr/local/bin/force-1080p.sh" "${SDCARD}/usr/local/bin/force-1080p.sh"
	mkdir -p "${SDCARD}"/etc/xdg/autostart
	run_host_command_logged install -m 644 "${SRC}/packages/bsp/common/etc/xdg/autostart/force-1080p.desktop" "${SDCARD}/etc/xdg/autostart/force-1080p.desktop"
}
