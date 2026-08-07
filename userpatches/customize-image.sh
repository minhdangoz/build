#!/bin/bash

# arguments: $RELEASE $LINUXFAMILY $BOARD $BUILD_DESKTOP
#
# This is the image customization script

# NOTE: It is copied to /tmp directory inside the image
# and executed there inside chroot environment
# so don't reference any files that are not already installed

# NOTE: If you want to transfer files between chroot and host
# userpatches/overlay directory on host is bind-mounted to /tmp/overlay in chroot
# The sd card's root path is accessible via $SDCARD variable.

RELEASE=$1
LINUXFAMILY=$2
BOARD=$3
BUILD_DESKTOP=$4

Main() {
	case ${BOARD} in
		tx68|km7)
			InstallFastfetch
			;;
		qemu-uefi-x86)
			InstallVmwareTools
			;;
		qemu-uefi-x86-tx68)
			InstallVmwareTools
			InstallFastfetch
			;;
	esac

	case $RELEASE in
		stretch)
			# your code here
			# InstallOpenMediaVault # uncomment to get an OMV 4 image
			;;
		buster)
			# your code here
			;;
		bullseye)
			# your code here
			;;
		bionic)
			# your code here
			;;
		focal)
			# your code here
			;;
		noble)
			case ${BOARD} in
				tx68|km7|qemu-uefi-x86-tx68)
					InstallBrowsers
					InstallStealthAgentFirstBoot
					;;
			esac
			;;
	esac
} # Main

InstallVmwareTools() {
	# VMware Workstation integration: clipboard, drag-and-drop, dynamic
	# resolution, shared folders, and clean guest shutdown/reboot handling.
	export DEBIAN_FRONTEND=noninteractive
	apt-get update
	apt-get install -y open-vm-tools open-vm-tools-desktop
	apt-get clean
} # InstallVmwareTools

InstallFastfetch() {
	# fastfetch isn't packaged for every release this project builds, and
	# versions in the ones that do carry it lag well behind upstream. Grab
	# the aarch64 .deb straight from the latest GitHub release instead.
	export DEBIAN_FRONTEND=noninteractive
	local workdir fastfetch_deb_url fastfetch_arch
	workdir=$(mktemp -d)
	case "$(dpkg --print-architecture)" in
		amd64) fastfetch_arch="amd64" ;;
		arm64) fastfetch_arch="aarch64" ;;
		*) echo "Unsupported fastfetch architecture: $(dpkg --print-architecture)" >&2; exit 1 ;;
	esac

	fastfetch_deb_url=$(curl -fsSL https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest \
		| grep -oE '"browser_download_url": *"[^"]*/fastfetch-linux-'"${fastfetch_arch}"'\.deb"' \
		| head -1 | cut -d'"' -f4)
	curl -fLo "${workdir}/fastfetch.deb" "${fastfetch_deb_url}"

	dpkg -i "${workdir}/fastfetch.deb" || apt-get -f install -y
	rm -rf "${workdir}"
} # InstallFastfetch

InstallBrowsers() {
	# TV-box and VMware images should come with real browsers preinstalled,
	# not just GNOME Web. Download the package matching the image architecture.
	export DEBIAN_FRONTEND=noninteractive
	local workdir deb_arch
	local -a curl_download=(curl -fL --retry 4 --retry-all-errors --retry-delay 2 \
		--connect-timeout 20 --speed-limit 102400 --speed-time 30)
	workdir=$(mktemp -d)
	deb_arch="$(dpkg --print-architecture)"
	case "${deb_arch}" in
		amd64|arm64) ;;
		*) echo "Unsupported browser architecture: ${deb_arch}" >&2; exit 1 ;;
	esac

	# Chrome publishes a stable "current" alias.
	"${curl_download[@]}" -o "${workdir}/google-chrome.deb" \
		"https://dl.google.com/linux/direct/google-chrome-stable_current_${deb_arch}.deb"

	# Vivaldi has no "current" alias -- the version has to be scraped out of
	# the download page first.
	local vivaldi_deb_url
	vivaldi_deb_url=$(curl -fsSL https://vivaldi.com/download/ \
		| grep -oE 'https://downloads\.vivaldi\.com/stable/vivaldi-stable_[^"]*'"${deb_arch}"'\.deb' | head -1)
	"${curl_download[@]}" -o "${workdir}/vivaldi.deb" "${vivaldi_deb_url}"

	# Brave's browser package depends on its repository/keyring package. Resolve
	# the current keyring from the official repository before installing Brave.
	local brave_deb_url brave_keyring_path brave_packages
	brave_packages=$(curl -fsSL \
		https://brave-browser-apt-release.s3.brave.com/dists/stable/main/binary-amd64/Packages)
	brave_keyring_path=$(awk '/^Package: brave-keyring$/ { found=1 } found && /^Filename:/ { print $2; exit }' \
		<<< "${brave_packages}")
	"${curl_download[@]}" -o "${workdir}/brave-keyring.deb" \
		"https://brave-browser-apt-release.s3.brave.com/${brave_keyring_path}"
	dpkg -i "${workdir}/brave-keyring.deb"

	# Brave only ships versioned browser assets, so resolve the matching
	# architecture from its latest GitHub release.
	brave_deb_url=$(curl -fsSL https://api.github.com/repos/brave/brave-browser/releases/latest \
		| grep -oE '"browser_download_url": *"[^"]*/brave-browser_[^"]*_'"${deb_arch}"'\.deb"' \
		| head -1 | cut -d'"' -f4)
	"${curl_download[@]}" -o "${workdir}/brave-browser.deb" "${brave_deb_url}"

	dpkg -i "${workdir}"/*.deb || apt-get -f install -y
	rm -rf "${workdir}"

	# Ubuntu dropped the real Chromium .deb in favor of a snap transitional
	# package, so pull actual Chromium builds from xtradeb/apps instead --
	# it packages upstream Chromium as a real arm64 .deb.
	apt-get install -y software-properties-common
	add-apt-repository -y ppa:xtradeb/apps
	apt-get update
	apt-get -o Dpkg::Options::=--force-confold install -y chromium

	apt-get clean
} # InstallBrowsers

InstallStealthAgentFirstBoot() {
	# Split by what is device-specific and what is not.
	#
	# Baked here (identical on every board, and a failure fails the build
	# loudly instead of 1000 devices quietly): runtime apt deps, the
	# source-built ydotool, and the ~300MB app/worker payloads. Doing these at
	# build time is what makes first boot cheap and offline-ish.
	#
	# Left for first boot (genuinely per-device, needs a real account/session/
	# hardware identity): running install_linux.sh itself, which registers the
	# OS service, wires the GUI guardian into the logged-in session and enables
	# AT-SPI for that user. Baking those once would clone one device's identity
	# onto every board.
	export DEBIAN_FRONTEND=noninteractive
	local base_url="https://ai.thanglam.info"
	local token="rQ87sJzUb0i39aKqjEODCh97P7RKxal990sfviuj0"
	local stage="/opt/stealth-agent-bootstrap"
	local payload_arch
	case "$(dpkg --print-architecture)" in
		amd64) payload_arch="amd64" ;;
		arm64) payload_arch="arm64" ;;
		*) echo "Unsupported Stealth Agent architecture: $(dpkg --print-architecture)" >&2; exit 1 ;;
	esac
	mkdir -p "${stage}" /etc/stealth-agent

	# Same runtime set install_linux.sh's install_apt would pull on the device.
	# Preinstalling means first boot resolves them from cache instead of
	# needing a healthy mirror before the agent can exist at all.
	local webkit_pkg alsa_pkg
	apt-cache show libwebkit2gtk-4.1-0 > /dev/null 2>&1 \
		&& webkit_pkg="libwebkit2gtk-4.1-0" || webkit_pkg="libwebkit2gtk-4.0-37"
	apt-cache show libasound2t64 > /dev/null 2>&1 \
		&& alsa_pkg="libasound2t64" || alsa_pkg="libasound2"
	apt-get update
	apt-get install -y \
		ca-certificates curl wget gnupg unzip git build-essential cmake pkg-config \
		xdg-utils xdotool x11-xserver-utils scrot gnome-screenshot python3-tk \
		xclip xsel wl-clipboard libgtk-3-0 "${webkit_pkg}" libayatana-appindicator3-1 \
		libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 \
		libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libgbm1 \
		libpango-1.0-0 libcairo2 "${alsa_pkg}" fonts-liberation \
		|| exit 1

	# install_linux.sh builds ydotool v1.0.4 from source (the distro package is
	# too old for --socket-own, which is what gives the desktop user its own
	# socket). Doing that here removes a git clone + compile -- and its hard
	# `fail` -- from every device's first boot. install_ydotool_daemon() skips
	# the build when these are already present.
	local ydotool_dir
	ydotool_dir="$(mktemp -d)"
	git clone --depth 1 --branch v1.0.4 https://github.com/ReimuNotMoe/ydotool.git "${ydotool_dir}/src" \
		&& cmake -S "${ydotool_dir}/src" -B "${ydotool_dir}/build" \
		&& cmake --build "${ydotool_dir}/build" --target ydotool ydotoold --parallel "$(nproc)" \
		|| exit 1
	install -D -m 0755 "${ydotool_dir}/build/ydotool" /usr/local/lib/stealth-agent/ydotool/ydotool
	install -D -m 0755 "${ydotool_dir}/build/ydotoold" /usr/local/lib/stealth-agent/ydotool/ydotoold
	rm -rf "${ydotool_dir}"

	# Payloads + the platform installer, resolved through the same API the
	# bootstrap install.sh uses. Downloading ~300MB once per image instead of
	# once per device removes the single biggest first-boot failure surface.
	curl -fsSL --retry 3 --connect-timeout 20 -H "Authorization: Bearer ${token}" \
		"${base_url}/downloads/install_linux.sh" -o "${stage}/install_linux.sh" || exit 1
	local pkg pkg_app pkg_out pkg_json pkg_url pkg_sha
	for pkg in "c-agent:app.zip" "auto-package:worker.zip"; do
		pkg_app="${pkg%%:*}"
		pkg_out="${stage}/${pkg#*:}"
		pkg_json="$(curl -fsSL --retry 3 --connect-timeout 20 -H "Authorization: Bearer ${token}" \
			"${base_url}/api/v1/check-desktop-update/${pkg_app}/linux/${payload_arch}")" || exit 1
		pkg_url="$(printf '%s' "${pkg_json}" | sed -n 's/.*"fileUrl":[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
		pkg_sha="$(printf '%s' "${pkg_json}" | sed -n 's/.*"sha256":[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
		[[ -n "${pkg_url}" && -n "${pkg_sha}" ]] || exit 1
		curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 \
			-H "Authorization: Bearer ${token}" -o "${pkg_out}" "${pkg_url}" || exit 1
		# A corrupt payload baked into the image would fail identically on every
		# board, so verify here where it is still one fixable build.
		echo "${pkg_sha}  ${pkg_out}" | sha256sum -c - || exit 1
	done

	cat > /etc/stealth-agent/firstboot.env <<ENVEOF
BASE_URL=${base_url}
INSTALL_TOKEN=${token}
STAGE_DIR=${stage}
PAYLOAD_ARCH=${payload_arch}
ENVEOF
	chmod 600 /etc/stealth-agent/firstboot.env

	cat > /usr/local/sbin/stealth-agent-firstboot.sh <<'EOF'
#!/bin/bash
# pipefail is required: a bare `set -eu` lets a failed curl still exit 0
# (bash reads zero bytes from the pipe and runs nothing), which would mark a
# device installed when nothing was installed.
set -euo pipefail

. /etc/stealth-agent/firstboot.env

APP=stealth-agent
STATUS_FILE=/etc/stealth-agent/.firstboot-status
SENTINEL=/etc/stealth-agent/.firstboot-installed
LOG_FILE=/var/log/stealth-agent-firstboot.log

mkdir -p /etc/stealth-agent
exec > >(tee -a "${LOG_FILE}") 2>&1

# Nobody can read a log on a box that failed to come up, so every state also
# goes to the HDMI console (these are TV boxes with a screen attached) and to
# a status file the MOTD prints on login.
say() {
  printf '%s %s\n' "$(date -Is)" "$*"
  if [[ -w /dev/tty1 ]]; then printf '[stealth-agent] %s\n' "$*" > /dev/tty1 || true; fi
}
status() { printf '%s | %s\n' "$(date -Is)" "$*" > "${STATUS_FILE}"; say "$*"; }

wait_for() {
  local label="$1" tries="$2"; shift 2
  status "waiting: ${label}"
  local i
  for ((i = 0; i < tries; i++)); do
    if "$@"; then return 0; fi
    sleep 5
  done
  return 1
}

LOGIN_USER="$(getent passwd 1000 | cut -d: -f1 || true)"
[[ -n "${LOGIN_USER}" ]] || { status "RETRY: no uid-1000 desktop user yet"; exit 1; }
LOGIN_UID="$(id -u "${LOGIN_USER}")"
USER_ENV=(XDG_RUNTIME_DIR="/run/user/${LOGIN_UID}" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${LOGIN_UID}/bus")

session_up() { [[ -S "/run/user/${LOGIN_UID}/bus" ]]; }
backend_up() {
  curl -fsS --max-time 15 -o /dev/null -H "Authorization: Bearer ${INSTALL_TOKEN}" \
    "${BASE_URL}/api/v1/check-desktop-update/c-agent/linux/${PAYLOAD_ARCH}"
}

# The installer only *warns* when the desktop session is missing, then leaves
# the guardian and AT-SPI unconfigured -- an install that exits 0 but can never
# automate anything. Waiting here is what stops that from being baked in.
wait_for "desktop session for ${LOGIN_USER}" 120 session_up \
  || { status "RETRY: no desktop session after 10m"; exit 1; }

# Link-up is not reachability; this also proves DNS, TLS and the token.
wait_for "backend reachable" 120 backend_up \
  || { status "RETRY: backend unreachable after 10m"; exit 1; }

status "installing from ${STAGE_DIR} (several minutes)"
rc=0
bash "${STAGE_DIR}/install_linux.sh" \
  --app-zip "${STAGE_DIR}/app.zip" \
  --worker-zip "${STAGE_DIR}/worker.zip" \
  --login-user "${LOGIN_USER}" \
  --install-token "${INSTALL_TOKEN}" \
  --app-env prod || rc=$?

# install_linux.sh downgrades most desktop wiring to warnings, so its exit code
# alone cannot say the device is usable. Check the things automation actually
# needs; anything missing means retry rather than a permanent silent failure.
problems=""
add_problem() { problems="${problems:+${problems}; }$1"; }
[[ -x "/opt/${APP}/${APP}" ]] || add_problem "agent binary missing"
runuser -u "${LOGIN_USER}" -- env "${USER_ENV[@]}" \
  gsettings get org.gnome.desktop.interface toolkit-accessibility 2>/dev/null \
  | grep -q true || add_problem "toolkit-accessibility off (xa11y would fail)"
runuser -u "${LOGIN_USER}" -- env "${USER_ENV[@]}" \
  systemctl --user is-active --quiet "${APP}-guardian.service" || add_problem "guardian not active"
systemctl is-active --quiet "${APP}-ydotoold.service" || add_problem "ydotoold not active"

if [[ ${rc} -eq 0 && -z "${problems}" ]]; then
  touch "${SENTINEL}"
  status "INSTALLED OK"
else
  status "RETRY in 60s: rc=${rc}${problems:+ | ${problems}} | log: ${LOG_FILE}"
  exit 1
fi
EOF
	chmod 755 /usr/local/sbin/stealth-agent-firstboot.sh

	# Anyone who SSHes in or opens a terminal sees the current state without
	# knowing which unit or log to look at.
	cat > /etc/update-motd.d/99-stealth-agent <<'EOF'
#!/bin/sh
[ -f /etc/stealth-agent/.firstboot-status ] || exit 0
printf '\n[stealth-agent] %s\n' "$(cat /etc/stealth-agent/.firstboot-status)"
[ -f /etc/stealth-agent/.firstboot-installed ] \
  || printf '  install not finished — journalctl -u stealth-agent-firstboot -f\n'
printf '\n'
EOF
	chmod 755 /etc/update-motd.d/99-stealth-agent

	cat > /etc/systemd/system/stealth-agent-firstboot.service <<'EOF'
[Unit]
Description=Stealth Agent first-boot install
After=network-online.target display-manager.service
Wants=network-online.target display-manager.service
ConditionPathExists=!/etc/stealth-agent/.firstboot-installed
StartLimitIntervalSec=0

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/stealth-agent-firstboot.sh
# Unlimited retries on purpose: these boxes are unattended, so a device that
# keeps retrying every minute is strictly better than one stuck forever. The
# script's own waits are bounded, so a retry always makes progress or reports.
Restart=on-failure
RestartSec=60
TimeoutStartSec=2400

[Install]
WantedBy=graphical.target
EOF
	chmod 644 /etc/systemd/system/stealth-agent-firstboot.service
	systemctl enable stealth-agent-firstboot.service
} # InstallStealthAgentFirstBoot

InstallOpenMediaVault() {
	# use this routine to create a Debian based fully functional OpenMediaVault
	# image (OMV 3 on Jessie, OMV 4 with Stretch). Use of mainline kernel highly
	# recommended!
	#
	# Please note that this variant changes Armbian default security 
	# policies since you end up with root password 'openmediavault' which
	# you have to change yourself later. SSH login as root has to be enabled
	# through OMV web UI first
	#
	# This routine is based on idea/code courtesy Benny Stark. For fixes,
	# discussion and feature requests please refer to
	# https://forum.armbian.com/index.php?/topic/2644-openmediavault-3x-customize-imagesh/

	echo root:openmediavault | chpasswd
	rm /root/.not_logged_in_yet
	. /etc/default/cpufrequtils
	export LANG=C LC_ALL="en_US.UTF-8"
	export DEBIAN_FRONTEND=noninteractive
	export APT_LISTCHANGES_FRONTEND=none

	case ${RELEASE} in
		jessie)
			OMV_Name="erasmus"
			OMV_EXTRAS_URL="https://github.com/OpenMediaVault-Plugin-Developers/packages/raw/master/openmediavault-omvextrasorg_latest_all3.deb"
			;;
		stretch)
			OMV_Name="arrakis"
			OMV_EXTRAS_URL="https://github.com/OpenMediaVault-Plugin-Developers/packages/raw/master/openmediavault-omvextrasorg_latest_all4.deb"
			;;
	esac

	# Add OMV source.list and Update System
	cat > /etc/apt/sources.list.d/openmediavault.list <<- EOF
	deb https://openmediavault.github.io/packages/ ${OMV_Name} main
	## Uncomment the following line to add software from the proposed repository.
	deb https://openmediavault.github.io/packages/ ${OMV_Name}-proposed main
	
	## This software is not part of OpenMediaVault, but is offered by third-party
	## developers as a service to OpenMediaVault users.
	# deb https://openmediavault.github.io/packages/ ${OMV_Name} partner
	EOF

	# Add OMV and OMV Plugin developer keys, add Cloudshell 2 repo for XU4
	if [ "${BOARD}" = "odroidxu4" ]; then
		add-apt-repository -y ppa:kyle1117/ppa
		sed -i 's/jessie/xenial/' /etc/apt/sources.list.d/kyle1117-ppa-jessie.list
	fi
	mount --bind /dev/null /proc/mdstat
	apt-get update
	apt-get --yes --force-yes --allow-unauthenticated install openmediavault-keyring
	apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 7AA630A1EDEE7D73
	apt-get update

	# install debconf-utils, postfix and OMV
	HOSTNAME="${BOARD}"
	debconf-set-selections <<< "postfix postfix/mailname string ${HOSTNAME}"
	debconf-set-selections <<< "postfix postfix/main_mailer_type string 'No configuration'"
	apt-get --yes --force-yes --allow-unauthenticated  --fix-missing --no-install-recommends \
		-o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install \
		debconf-utils postfix
	# move newaliases temporarely out of the way (see Ubuntu bug 1531299)
	cp -p /usr/bin/newaliases /usr/bin/newaliases.bak && ln -sf /bin/true /usr/bin/newaliases
	sed -i -e "s/^::1         localhost.*/::1         ${HOSTNAME} localhost ip6-localhost ip6-loopback/" \
		-e "s/^127.0.0.1   localhost.*/127.0.0.1   ${HOSTNAME} localhost/" /etc/hosts
	sed -i -e "s/^mydestination =.*/mydestination = ${HOSTNAME}, localhost.localdomain, localhost/" \
		-e "s/^myhostname =.*/myhostname = ${HOSTNAME}/" /etc/postfix/main.cf
	apt-get --yes --force-yes --allow-unauthenticated  --fix-missing --no-install-recommends \
		-o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install \
		openmediavault

	# install OMV extras, enable folder2ram and tweak some settings
	FILE=$(mktemp)
	curl "$OMV_EXTRAS_URL" -fLso "$FILE" && dpkg -i "$FILE"
	
	/usr/sbin/omv-update
	# Install flashmemory plugin and netatalk by default, use nice logo for the latter,
	# tweak some OMV settings
	. /usr/share/openmediavault/scripts/helper-functions
	apt-get -y -q install openmediavault-netatalk openmediavault-flashmemory
	AFP_Options="mimic model = Macmini"
	SMB_Options="min receivefile size = 16384\nwrite cache size = 524288\ngetwd cache = yes\nsocket options = TCP_NODELAY IPTOS_LOWDELAY"
	xmlstarlet ed -L -u "/config/services/afp/extraoptions" -v "$(echo -e "${AFP_Options}")" /etc/openmediavault/config.xml
	xmlstarlet ed -L -u "/config/services/smb/extraoptions" -v "$(echo -e "${SMB_Options}")" /etc/openmediavault/config.xml
	xmlstarlet ed -L -u "/config/services/flashmemory/enable" -v "1" /etc/openmediavault/config.xml
	xmlstarlet ed -L -u "/config/services/ssh/enable" -v "1" /etc/openmediavault/config.xml
	xmlstarlet ed -L -u "/config/services/ssh/permitrootlogin" -v "0" /etc/openmediavault/config.xml
	xmlstarlet ed -L -u "/config/system/time/ntp/enable" -v "1" /etc/openmediavault/config.xml
	xmlstarlet ed -L -u "/config/system/time/timezone" -v "UTC" /etc/openmediavault/config.xml
	xmlstarlet ed -L -u "/config/system/network/dns/hostname" -v "${HOSTNAME}" /etc/openmediavault/config.xml
	xmlstarlet ed -L -u "/config/system/monitoring/perfstats/enable" -v "0" /etc/openmediavault/config.xml
	echo -e "OMV_CPUFREQUTILS_GOVERNOR=${GOVERNOR}" >>/etc/default/openmediavault
	echo -e "OMV_CPUFREQUTILS_MINSPEED=${MIN_SPEED}" >>/etc/default/openmediavault
	echo -e "OMV_CPUFREQUTILS_MAXSPEED=${MAX_SPEED}" >>/etc/default/openmediavault
	for i in netatalk samba flashmemory ssh ntp timezone interfaces cpufrequtils monit collectd rrdcached ; do
		/usr/sbin/omv-mkconf $i
	done
	/sbin/folder2ram -enablesystemd || true
	sed -i 's|-j /var/lib/rrdcached/journal/ ||' /etc/init.d/rrdcached

	# Fix multiple sources entry on ARM with OMV4
	sed -i '/stretch-backports/d' /etc/apt/sources.list

	# rootfs resize to 7.3G max and adding omv-initsystem to firstrun -- q&d but shouldn't matter
	echo 15500000s >/root/.rootfs_resize
	sed -i '/systemctl\ disable\ armbian-firstrun/i \
	mv /usr/bin/newaliases.bak /usr/bin/newaliases \
	export DEBIAN_FRONTEND=noninteractive \
	sleep 3 \
	apt-get install -f -qq python-pip python-setuptools || exit 0 \
	pip install -U tzupdate \
	tzupdate \
	read TZ </etc/timezone \
	/usr/sbin/omv-initsystem \
	xmlstarlet ed -L -u "/config/system/time/timezone" -v "${TZ}" /etc/openmediavault/config.xml \
	/usr/sbin/omv-mkconf timezone \
	lsusb | egrep -q "0b95:1790|0b95:178a|0df6:0072" || sed -i "/ax88179_178a/d" /etc/modules' /usr/lib/armbian/armbian-firstrun
	sed -i '/systemctl\ disable\ armbian-firstrun/a \
	sleep 30 && sync && reboot' /usr/lib/armbian/armbian-firstrun

	# add USB3 Gigabit Ethernet support
	echo -e "r8152\nax88179_178a" >>/etc/modules

	# Special treatment for ODROID-XU4 (and later Amlogic S912, RK3399 and other big.LITTLE
	# based devices). Move all NAS daemons to the big cores. With ODROID-XU4 a lot
	# more tweaks are needed. CS2 repo added, CS1 workaround added, coherent_pool=1M
	# set: https://forum.odroid.com/viewtopic.php?f=146&t=26016&start=200#p197729
	# (latter not necessary any more since we fixed it upstream in Armbian)
	case ${BOARD} in
		odroidxu4)
			HMP_Fix='; taskset -c -p 4-7 $i '
			# Cloudshell stuff (fan, lcd, missing serials on 1st CS2 batch)
			echo "H4sIAKdXHVkCA7WQXWuDMBiFr+eveOe6FcbSrEIH3WihWx0rtVbUFQqCqAkYGhJn
			tF1x/vep+7oebDfh5DmHwJOzUxwzgeNIpRp9zWRegDPznya4VDlWTXXbpS58XJtD
			i7ICmFBFxDmgI6AXSLgsiUop54gnBC40rkoVA9rDG0SHHaBHPQx16GN3Zs/XqxBD
			leVMFNAz6n6zSWlEAIlhEw8p4xTyFtwBkdoJTVIJ+sz3Xa9iZEMFkXk9mQT6cGSQ
			QL+Cr8rJJSmTouuuRzfDtluarm1aLVHksgWmvanm5sbfOmY3JEztWu5tV9bCXn4S
			HB8RIzjoUbGvFvPw/tmr0UMr6bWSBupVrulY2xp9T1bruWnVga7DdAqYFgkuCd3j
			vORUDQgej9HPJxmDDv+3WxblBSuYFH8oiNpHz8XvPIkU9B3JVCJ/awIAAA==" \
			| tr -d '[:blank:]' | base64 --decode | gunzip -c >/usr/local/sbin/cloudshell2-support.sh
			chmod 755 /usr/local/sbin/cloudshell2-support.sh
			apt install -y i2c-tools odroid-cloudshell cloudshell2-fan
			sed -i '/systemctl\ disable\ armbian-firstrun/i \
			lsusb | grep -q -i "05e3:0735" && sed -i "/exit\ 0/i echo 20 > /sys/class/block/sda/queue/max_sectors_kb" /etc/rc.local \
			/usr/sbin/i2cdetect -y 1 | grep -q "60: 60" && /usr/local/sbin/cloudshell2-support.sh' /usr/lib/armbian/armbian-firstrun
			;;
		bananapim3)
			HMP_Fix='; taskset -c -p 4-7 $i '
			;;
		edge*|ficus|firefly-rk3399|nanopct4|nanopim4|nanopineo4|renegade-elite|roc-rk3399-pc|rockpro64|station-p1)
			HMP_Fix='; taskset -c -p 4-5 $i '
			;;
	esac
	echo "* * * * * root for i in \`pgrep \"ftpd|nfsiod|smbd|afpd|cnid\"\` ; do ionice -c1 -p \$i ${HMP_Fix}; done >/dev/null 2>&1" \
		>/etc/cron.d/make_nas_processes_faster
	chmod 600 /etc/cron.d/make_nas_processes_faster

	# add SATA port multiplier hint if appropriate
	[ "${LINUXFAMILY}" = "sunxi" ] && \
		echo -e "#\n# If you want to use a SATA PM add \"ahci_sunxi.enable_pmp=1\" to bootargs above" \
		>>/boot/boot.cmd

	# Filter out some log messages
	echo ':msg, contains, "do ionice -c1" ~' >/etc/rsyslog.d/omv-armbian.conf
	echo ':msg, contains, "action " ~' >>/etc/rsyslog.d/omv-armbian.conf
	echo ':msg, contains, "netsnmp_assert" ~' >>/etc/rsyslog.d/omv-armbian.conf
	echo ':msg, contains, "Failed to initiate sched scan" ~' >>/etc/rsyslog.d/omv-armbian.conf

	# Fix little python bug upstream Debian 9 obviously ignores
	if [ -f /usr/lib/python3.5/weakref.py ]; then
		GITREF="9cd7e17640a49635d1c1f8c2989578a8fc2c1de6"
		curl -fLo /usr/lib/python3.5/weakref.py \
			"https://raw.githubusercontent.com/python/cpython/${GITREF}/Lib/weakref.py"
	fi

	# clean up and force password change on first boot
	umount /proc/mdstat
	chage -d 0 root
} # InstallOpenMediaVault

UnattendedStorageBenchmark() {
	# Function to create Armbian images ready for unattended storage performance testing.
	# Useful to use the same OS image with a bunch of different SD cards or eMMC modules
	# to test for performance differences without wasting too much time.

	rm /root/.not_logged_in_yet

	apt-get -qq install time

	curl -fLso /usr/local/bin/sd-card-bench.sh "https://raw.githubusercontent.com/ThomasKaiser/sbc-bench/master/sd-card-bench.sh"
	chmod 755 /usr/local/bin/sd-card-bench.sh

	sed -i '/^exit\ 0$/i \
	/usr/local/bin/sd-card-bench.sh &' /etc/rc.local
} # UnattendedStorageBenchmark

InstallAdvancedDesktop()
{
	apt-get install -yy transmission libreoffice libreoffice-style-tango meld remmina thunderbird kazam avahi-daemon
	[[ -f /usr/share/doc/avahi-daemon/examples/sftp-ssh.service ]] && cp /usr/share/doc/avahi-daemon/examples/sftp-ssh.service /etc/avahi/services/
	[[ -f /usr/share/doc/avahi-daemon/examples/ssh.service ]] && cp /usr/share/doc/avahi-daemon/examples/ssh.service /etc/avahi/services/
	apt clean
} # InstallAdvancedDesktop

Main "$@"
