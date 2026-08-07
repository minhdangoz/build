# x86_64 VMware/QEMU development twin of TX68.
#
# This deliberately clones TX68's architecture-independent user experience
# and management surface while retaining virtual x86 boot, kernel and device
# drivers. H618-only GPU, Wi-Fi/Bluetooth, FD650 and eMMC hooks must remain in
# tx68.conf and are not valid inside a virtual machine.

declare -g BOARD_NAME="TX68 development VM (UEFI x86)"
declare -g BOARD_VENDOR="generic"
declare -g BOARDFAMILY="uefi-x86"
declare -g BOARD_MAINTAINER="jimmy"
declare -g INTRODUCED="2026"
declare -g KERNEL_TARGET="current"
declare -g SERIALCON="tty1,ttyS0"

declare -g BOOT_LOGO=desktop
declare -g GRUB_CMDLINE_LINUX_DEFAULT="earlyprintk=ttyS0,115200,keep"
declare -g DEFAULT_CONSOLE="both"
declare -g UEFI_GRUB_TERMINAL="gfxterm vga_text console serial"

# Match the unattended TX68 login contract.
declare -g ROOTPWD="tx68"
declare -g DESKTOP_AUTOLOGIN="yes"
declare -g CONSOLE_AUTOLOGIN="yes"
declare -g PACKAGE_LIST_BOARD="net-tools"

function post_family_tweaks__qemu_uefi_x86_tx68() {
	display_alert "${BOARD}" "Applying TX68 userland configuration to x86 VM" "info"

	# Match the TX68 GNOME/X11 session and kiosk power/lock policy. X11 is
	# retained because the deployed TX68 automation and x11vnc paths own :0.
	if [[ -d "${SDCARD}/etc/gdm3" || "${DESKTOP_ENVIRONMENT}" == "gnome" ]]; then
		chroot_sdcard_apt_get_install gjs
		mkdir -p "${SDCARD}/etc/gdm3" "${SDCARD}/etc/dconf/db/local.d"
		cat <<- 'GDM_X11' > "${SDCARD}/etc/gdm3/custom.conf"
			[daemon]
			WaylandEnable=false
			AutomaticLoginEnable=true
			AutomaticLogin=tx68
		GDM_X11
		cat <<- 'DCONF_NOLOCK' > "${SDCARD}/etc/dconf/db/local.d/02-tx68-no-lock"
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

	# Build the same account and group membership as the physical TX68 and
	# remove Armbian's interactive first-login trigger completely.
	chroot_sdcard "useradd --create-home --home-dir /home/tx68 --shell /bin/bash --comment TX68 --user-group tx68 || true"
	chroot_sdcard "echo 'tx68:tx68' | chpasswd"
	chroot_sdcard "for g in sudo netdev audio video disk tty users games dialout plugdev input bluetooth systemd-journal ssh render docker; do getent group \"\$g\" >/dev/null && usermod -aG \"\$g\" tx68; done; true"
	rm -f "${SDCARD}/root/.not_logged_in_yet"
	touch "${SDCARD}/root/.desktop_autologin"

	# Match TX68's remote administration surface. VMware console/clipboard is
	# additional; SSH and x11vnc remain available exactly as on the box.
	chroot_sdcard_apt_get_install openssh-server x11vnc
	chroot_sdcard "x11vnc -storepasswd tx68 /etc/x11vnc.pass"
	run_host_command_logged install -m 644 "${SRC}/packages/bsp/common/lib/systemd/system/x11vnc.service" "${SDCARD}/lib/systemd/system/x11vnc.service"
	chroot_sdcard systemctl --no-reload enable x11vnc.service ssh.service
}
