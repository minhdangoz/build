# TX68 H618 eMMC boot script
#
# The packed working FDT comes from Android m1k_go. Do not apply the Orange Pi
# Zero 3 boot-time MMC/display mutations here.

setenv load_addr "0x45000000"
setenv rootdev "/dev/mmcblk0p1"
setenv verbosity "1"
setenv rootfstype "ext4"
setenv console "both"
setenv docker_optimizations "off"
setenv bootlogo "false"
setenv debug_uart "ttyAS0"

echo "TX68 boot script loaded from ${devtype} ${devnum}"

# The m1k_go DTS already selects HDMI mode 10 (1080p60), but its fb0 geometry
# is fixed at 1280x720.  The vendor fbdev driver exposes only that framebuffer
# geometry to Xorg/XRandR, so force a matching 1920x1080 desktop framebuffer.
fdt set /soc@3000000/disp@1000000 screen0_output_mode <10>
fdt set /soc@3000000/disp@1000000 dev0_output_mode <10>
fdt set /soc@3000000/disp@1000000 fb0_width <1920>
fdt set /soc@3000000/disp@1000000 fb0_height <1080>

if test -e ${devtype} ${devnum} ${prefix}orangepiEnv.txt; then
	load ${devtype} ${devnum} ${load_addr} ${prefix}orangepiEnv.txt
	env import -t ${load_addr} ${filesize}
fi

if test "${console}" = "display" || test "${console}" = "both"; then setenv consoleargs "console=${debug_uart},115200 console=tty1"; fi
if test "${console}" = "serial"; then setenv consoleargs "console=${debug_uart},115200"; fi
if test "${bootlogo}" = "true"; then
	setenv consoleargs "splash plymouth.ignore-serial-consoles ${consoleargs}"
else
	setenv consoleargs "splash=verbose ${consoleargs}"
fi

if test "${devtype}" = "mmc"; then part uuid ${devtype} ${devnum}:1 partuuid; fi

setenv bootargs "root=${rootdev} rootwait rootfstype=${rootfstype} ${consoleargs} consoleblank=0 loglevel=${verbosity} ubootpart=${partuuid} disp_reserve=${disp_reserve} ${extraargs} ${extraboardargs}"

if test "${docker_optimizations}" = "on"; then setenv bootargs "${bootargs} cgroup_enable=memory swapaccount=1"; fi

for overlay_file in ${overlays}; do
	if load ${devtype} ${devnum} ${load_addr} ${prefix}dtb/sunxi/overlay/${overlay_prefix}-${overlay_file}.dtbo; then
		echo "Applying kernel provided DT overlay ${overlay_prefix}-${overlay_file}.dtbo"
		fdt apply ${load_addr} || setenv overlay_error "true"
	fi
done

for overlay_file in ${user_overlays}; do
	if load ${devtype} ${devnum} ${load_addr} ${prefix}overlay-user/${overlay_file}.dtbo; then
		echo "Applying user overlay ${overlay_file}.dtbo"
		fdt apply ${load_addr} || setenv overlay_error "true"
	fi
done

load ${devtype} ${devnum} ${ramdisk_addr_r} ${prefix}uInitrd
load ${devtype} ${devnum} ${kernel_addr_r} ${prefix}uImage

bootm ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}

# Recompile with:
# mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr
