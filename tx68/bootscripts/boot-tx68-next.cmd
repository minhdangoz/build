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
# kernel_addr_r is the uImage HEADER address, deliberately 0x40 below the
# 2MiB-aligned 0x41000000 that the header declares as load/entry. That puts
# the payload (after the 64-byte header) exactly at its load address, so
# bootm takes the IH_COMP_NONE "XIP" path (common/bootm.c image_decomp:
# `if (load == image_start) break;`) and skips the memmove whose size check
# tripped "Image too large: increase CONFIG_SYS_BOOTM_LEN" on real hardware
# -- sun50iw9p1.h caps CONFIG_SYS_BOOTM_LEN at 0x2000000 (32 MiB), and the
# mainline kernel is 38.3 MiB. No U-Boot rebuild needed this way.
setenv kernel_addr_r "0x40ffffc0"
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
	# Linux picks the *last* valid console= entry as the one /dev/console
	# actually opens (used by /init, getty, systemd, ...); every console=
	# still gets kernel printk output, but only the last one is what
	# userspace's own stdout/stdin binds to. With tty1 listed last, the
	# entire userspace side of boot (initramfs's own /init included) was
	# writing to the HDMI framebuffer console -- which never showed
	# anything (no working display driver/monitor sync yet) -- while we
	# only ever watched ttyS0, which only ever carries the kernel's own
	# printk lines. That looked exactly like a boot hang (kernel messages
	# stop, nothing else ever appears) even on a fully successful boot.
	# List ttyS0 last so /dev/console is the serial port we can actually see.
	setenv consoleargs "earlycon=uart8250,mmio32,0x05000000 console=tty1 console=ttyS0,115200 keep_bootcon"
fi
if test "${console}" = "serial"; then
	setenv consoleargs "earlycon=uart8250,mmio32,0x05000000 console=ttyS0,115200 keep_bootcon"
fi

if test "${devtype}" = "mmc"; then
	part uuid ${devtype} ${devnum}:1 partuuid
fi

# Visible-on-purpose marker, bumped by hand whenever this boot script or the
# initrd packaging changes in a way worth telling apart at a glance in the
# "Kernel command line" log line -- cheaper than comparing SHA-256/filenames
# across a long debugging session with many near-identical image builds.
setenv tx68_bootscript_ver "6-heartbeat"

setenv bootargs "root=${rootdev} rootwait rootfstype=${rootfstype} ${consoleargs} consoleblank=0 loglevel=${verbosity} ubootpart=${partuuid} tx68_bootscript_ver=${tx68_bootscript_ver} ${extraargs} ${extraboardargs}"
if test "${docker_optimizations}" = "on"; then
	setenv bootargs "${bootargs} cgroup_enable=memory swapaccount=1"
fi

load ${devtype} ${devnum} ${fdt_addr_r} ${prefix}dtb/allwinner/sun50i-h616-tx68.dtb
load ${devtype} ${devnum} ${ramdisk_addr_r} ${prefix}uInitrd
load ${devtype} ${devnum} ${kernel_addr_r} ${prefix}uImage

# Real hardware: kernel booted clean, but "Initramfs unpacking failed: invalid
# magic at start of compressed archive". Verified offline (extracted the raw
# initrd.img from the rootfs, re-ran the exact mkimage wrap the packaging
# script uses, gzip -t + byte-compare against the original payload) that the
# uInitrd file itself is not corrupt. The corruption happens on-device during
# `bootm`'s own ramdisk relocation: the log shows
#   "Loading Ramdisk to 48c43000, end 49ffffdd ... OK"
# i.e. bootm copied the ramdisk from ramdisk_addr_r up into
# 0x48c43000-0x49ffffdd -- squarely inside 0x48000000-0x48ffffff, which the
# kernel's own DT reserves as "non-reusable bl31" secure-monitor memory (see
# the "OF: reserved mem" line right after "Machine model" in the same log).
# U-Boot's LMB accounting only knows about *its own* embedded FDT/text/stack,
# not the kernel's BL31 reservation, so boot_ramdisk_high() (common/image.c)
# happily relocates straight into BL31's memory -- overwritten/scrubbed by
# the secure monitor before the kernel ever unpacks it. Setting initrd_high
# to the max u32 tells boot_ramdisk_high() to skip the relocation entirely
# (initrd_copy_to_ram = 0) and use ramdisk_addr_r exactly as loaded, which is
# already a safe, non-overlapping address.
setenv initrd_high "0xffffffff"

bootm ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}
