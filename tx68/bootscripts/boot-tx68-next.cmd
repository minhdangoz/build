# TX68 mainline-kernel canary.  U-Boot still sees the soldered eMMC as mmc2;
# Linux mainline enumerates that same root device as mmcblk0.
#
# kernel_addr_r/fdt_addr_r/ramdisk_addr_r must NOT be left at the vendor
# U-Boot's inherited defaults here (0x41000000/0x43000000/0x43300000 from
# u-boot/v2018.05-h618's include/configs/sunxi-common.h). Those were sized
# for the old vendor 5.4 uImage (26.67 MiB, see TX68_PORTING.md). The
# mainline Image is ~38.3 MiB, loaded *last* below, so with the inherited
# addresses it overruns 0x43000000 and overwrites the just-loaded FDT (and
# the start of the initrd) before booti ever runs -- silent failure, no
# display, no console, because Linux never gets far enough to touch either.
# These addresses give the kernel an 80 MiB window, well clear of the ATF
# BL31 reservation at 0x48000000-0x49000000 documented in TX68_PORTING.md.
#
# This U-Boot's actual .config (u-boot/v2018.05-h618/.config) has
# CONFIG_ARM=y, not CONFIG_ARM64 -- it is a 32-bit U-Boot proper that jumps
# to an AArch64 kernel via arch/arm/lib/bootm.c's armv8_switch_to_el1/el2,
# gated on the legacy uImage header's IH_ARCH_ARM64 tag. Only
# CONFIG_CMD_BOOTD/BOOTM/BOOTZ are enabled; CONFIG_CMD_BOOTI is not (it
# `depends on ARM64 || RISCV`, neither true here), so `booti` is an unknown
# command here -- it would fail silently on the serial console with no
# display output at all, which is exactly the symptom seen on real hardware.
# The kernel must therefore be a legacy uImage tagged -A arm64, booted with
# `bootm`, the same mechanism the working vendor 5.4 image already uses.
# tx68-build-phoenix-image.sh wraps armbian's raw /boot/Image into
# /boot/uImage with mkimage before packaging; this script loads that.
setenv kernel_addr_r "0x41000000"
setenv fdt_addr_r "0x46000000"
setenv ramdisk_addr_r "0x46400000"

setenv load_addr "0x45000000"
setenv rootdev "/dev/mmcblk0p1"
setenv verbosity "7"
setenv rootfstype "ext4"
setenv console "both"
setenv docker_optimizations "on"
setenv bootlogo "false"

echo "TX68 Linux 6.18 canary boot script loaded from ${devtype} ${devnum}"

if test -e ${devtype} ${devnum} ${prefix}orangepiEnv.txt; then
	load ${devtype} ${devnum} ${load_addr} ${prefix}orangepiEnv.txt
	env import -t ${load_addr} ${filesize}
fi

if test "${console}" = "display" || test "${console}" = "both"; then
	setenv consoleargs "console=ttyS0,115200 console=tty1"
fi
if test "${console}" = "serial"; then
	setenv consoleargs "console=ttyS0,115200"
fi

if test "${devtype}" = "mmc"; then
	part uuid ${devtype} ${devnum}:1 partuuid
fi

setenv bootargs "root=${rootdev} rootwait rootfstype=${rootfstype} ${consoleargs} consoleblank=0 loglevel=${verbosity} ubootpart=${partuuid} ${extraargs} ${extraboardargs}"
if test "${docker_optimizations}" = "on"; then
	setenv bootargs "${bootargs} cgroup_enable=memory swapaccount=1"
fi

load ${devtype} ${devnum} ${fdt_addr_r} ${prefix}dtb/allwinner/sun50i-h616-tx68.dtb
load ${devtype} ${devnum} ${ramdisk_addr_r} ${prefix}uInitrd
load ${devtype} ${devnum} ${kernel_addr_r} ${prefix}uImage

bootm ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}
