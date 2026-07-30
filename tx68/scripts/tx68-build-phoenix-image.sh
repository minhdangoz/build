#!/usr/bin/env bash

set -euo pipefail

usage()
{
	cat <<'EOF'
Usage:
  tx68/scripts/tx68-build-phoenix-image.sh RAW_UBUNTU_IMAGE [OUTPUT_PHOENIX_IMAGE]

Self-contained under armbian-build/tx68/ -- no dependency on any other
checkout's location except the one thing that's inherent to the device
itself, not to any particular repo layout: the Android BSP's secure-boot
keys, Boot0, and TOC1 templates (tx68/android-pack/, copied from
/home/jimmy/AOSP/pp618 -- TX68's BootROM only accepts a TOC1 signed with
these exact vendor keys, there is no way around needing them from somewhere).

Environment:
  ANDROID_PACK  Local copy of the Android pack_out/pctools/keys/sign_config
                tree (default: tx68/android-pack, alongside this script).
  TX68_BOOT_CMD Boot script to install into /boot (default:
                tx68/bootscripts/boot-tx68.cmd, the vendor 5.4 uImage flow).
                Pass .../boot-tx68-next.cmd for a mainline Image+dtb rootfs,
                e.g. one built by armbian-build's own tx68.conf board profile.
  TX68_UBOOT_DEB U-Boot .deb to sign and pack (default: the BRANCH=current
                one, tx68/uboot-debs/linux-u-boot-current-tx68_0.1.0_arm64.deb).
                Pass the BRANCH=next one (linux-u-boot-next-tx68_..._arm64.deb)
                when pairing with a mainline-kernel rootfs -- it embeds the
                mainline control FDT (see tx68/pack-uboot/bin/dts/tx68-u-boot.dts)
                that this vendor U-Boot's bootm always uses, regardless of
                what a boot script loads into fdt_addr_r.
EOF
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
	usage >&2
	exit 2
fi

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RAW_IMAGE="$(readlink -f "$1")"
ANDROID_PACK="${ANDROID_PACK:-${SRC}/android-pack}"
PACK_BASE="${ANDROID_PACK}/pack_out"
TOOLS="${ANDROID_PACK}/pctools-linux"
BSP_OPENSSL_DIR="${TOOLS}/openssl"
BSP_OPENSSL="${BSP_OPENSSL_DIR}/openssl"
SECURE_KEYS="${ANDROID_PACK}/keys"
SECURE_CNF="${ANDROID_PACK}/sign_config/cnf_base.cnf"
UBOOT_DEB="${TX68_UBOOT_DEB:-${SRC}/uboot-debs/linux-u-boot-current-tx68_0.1.0_arm64.deb}"
PHOENIX_DIR="${SRC}/../output/phoenix"
BUILD_STAMP="$(date +%Y%m%d_%H-%M-%S)"

if [[ ! -f "${RAW_IMAGE}" ]]; then
	echo "ERROR: raw Ubuntu image not found: ${RAW_IMAGE}" >&2
	exit 1
fi

if [[ $# -eq 2 ]]; then
	requested_output="$(readlink -m "$2")"
	requested_dir="$(dirname "${requested_output}")"
	requested_name="$(basename "${requested_output}")"
	requested_stem="${requested_name%.img}"
	if [[ ${requested_stem} == *_phoenixsuite ]]; then
		requested_stem="${requested_stem%_phoenixsuite}_${BUILD_STAMP}_phoenixsuite"
	else
		requested_stem="${requested_stem}_${BUILD_STAMP}"
	fi
	OUTPUT_IMAGE="${requested_dir}/${requested_stem}.img"
else
	raw_base="$(basename "${RAW_IMAGE}" .img)"
	OUTPUT_IMAGE="${PHOENIX_DIR}/${raw_base}_${BUILD_STAMP}_phoenixsuite.img"
fi

if [[ -e "${OUTPUT_IMAGE}" || -e "${OUTPUT_IMAGE}.sha256" ]]; then
	echo "ERROR: timestamped output already exists: ${OUTPUT_IMAGE}" >&2
	exit 1
fi

required_commands=(busybox cmp dd debugfs dpkg-deb e2fsck jq mkimage openssl sfdisk sha256sum strings xxd)
for command_name in "${required_commands[@]}"; do
	command -v "${command_name}" >/dev/null ||
		{ echo "ERROR: missing host command: ${command_name}" >&2; exit 1; }
done

required_tools=(
	"${TOOLS}/android/img2simg"
	"${TOOLS}/android/simg2img"
	"${TOOLS}/eDragonEx/dragon"
	"${TOOLS}/mod_update/parser_img"
	"${TOOLS}/mod_update/script"
	"${TOOLS}/mod_update/update_mbr"
	"${TOOLS}/openssl/dragonsecboot"
	"${BSP_OPENSSL}"
)
for tool in "${required_tools[@]}"; do
	[[ -x "${tool}" ]] ||
		{ echo "ERROR: missing Android BSP tool: ${tool}" >&2; exit 1; }
done

[[ -d "${PACK_BASE}" ]] ||
	{ echo "ERROR: Android pack_out not found: ${PACK_BASE}" >&2; exit 1; }
[[ -d "${SECURE_KEYS}" && -f "${SECURE_CNF}" ]] ||
	{ echo "ERROR: Android secure-boot keys/config not found" >&2; exit 1; }
[[ -f "${UBOOT_DEB}" ]] ||
	{ echo "ERROR: TX68 U-Boot package not found: ${UBOOT_DEB}" >&2; exit 1; }

partition_count="$(sfdisk --json "${RAW_IMAGE}" | jq '.partitiontable.partitions | length')"
sector_size="$(sfdisk --json "${RAW_IMAGE}" | jq '.partitiontable.sectorsize')"
partition_start="$(sfdisk --json "${RAW_IMAGE}" | jq '.partitiontable.partitions[0].start')"
partition_sectors="$(sfdisk --json "${RAW_IMAGE}" | jq '.partitiontable.partitions[0].size')"
partition_type="$(sfdisk --json "${RAW_IMAGE}" | jq -r '.partitiontable.partitions[0].type')"

if [[ "${partition_count}" -ne 1 || "${sector_size}" -ne 512 || "${partition_type}" != "83" ]]; then
	echo "ERROR: expected one 512-byte-sector Linux partition, got count=${partition_count} sector_size=${sector_size} type=${partition_type}" >&2
	exit 1
fi

if (( partition_start % 2048 != 0 || partition_sectors % 2048 != 0 )); then
	echo "ERROR: root partition must be aligned to 1 MiB" >&2
	exit 1
fi

# Round the Phoenix partition up to 16 MiB and leave one extra 16 MiB extent.
rootfs_sectors="$(( ((partition_sectors + 32768 + 32767) / 32768) * 32768 ))"
emmc_sectors=15269888
logical_start=40960
if (( rootfs_sectors + logical_start >= emmc_sectors )); then
	echo "ERROR: rootfs (${rootfs_sectors} sectors) does not fit the conservative m1k_go eMMC layout" >&2
	exit 1
fi

mkdir -p "${PHOENIX_DIR}" "$(dirname "${OUTPUT_IMAGE}")"
work_dir="$(mktemp -d "${PHOENIX_DIR}/.tx68-phoenix.XXXXXX")"
trap 'rm -rf -- "${work_dir}"' EXIT

pack_dir="${work_dir}/pack"
uboot_dir="${work_dir}/uboot"
secure_dir="${work_dir}/secure-toc1"
mkdir -p "${pack_dir}" "${uboot_dir}" "${secure_dir}"

base_files=(
	sys_config.fex board.fex config.fex split_xxxx.fex sunxi.fex
	monitor.fex optee.fex
	boot0_nand.fex u-boot.fex u-boot-crash.fex toc1.fex toc0.fex fes1.fex
	usbtool.fex usbtool_crash.fex aultools.fex aultls32.fex
	cardtool.fex cardscript.fex
)
for file_name in "${base_files[@]}"; do
	[[ -f "${PACK_BASE}/${file_name}" ]] ||
		{ echo "ERROR: missing known-good m1k_go pack input: ${file_name}" >&2; exit 1; }
	cp -a "${PACK_BASE}/${file_name}" "${pack_dir}/${file_name}"
done

dpkg-deb -x "${UBOOT_DEB}" "${uboot_dir}"
uboot_payload="${uboot_dir}/usr/lib/$(basename "${UBOOT_DEB}" _arm64.deb)_arm64"
[[ -d "${uboot_payload}" ]] ||
	{ echo "ERROR: expected U-Boot payload dir not found: ${uboot_payload}" >&2; exit 1; }
cp "${uboot_payload}/boot_package.fex" "${pack_dir}/boot_package.fex"
[[ -f "${uboot_payload}/u-boot.fex" ]] ||
	{ echo "ERROR: TX68 U-Boot DEB does not contain secure TOC1 payload u-boot.fex" >&2; exit 1; }

# Keep the Android u-boot.fex in pack_dir: PhoenixSuit runs it as FES2 in
# workmode 16 to perform the actual eMMC burn. Ubuntu U-Boot belongs only
# inside the signed TOC1; using it as FES2 makes PhoenixSuit autoboot instead
# of entering the burn protocol.
secure_files=(dragon_toc.cfg version_base.mk monitor.fex optee.fex sunxi.fex)
for file_name in "${secure_files[@]}"; do
	cp -a "${PACK_BASE}/${file_name}" "${secure_dir}/${file_name}"
done
cp -L "${PACK_BASE}/vbmeta.fex" "${secure_dir}/vbmeta.fex"
cp "${uboot_payload}/u-boot.fex" "${secure_dir}/u-boot.fex"

echo "Signing secure TOC1 with the m1k_go root key"
(
	cd "${secure_dir}"
	# dragonsecboot shells out to an unqualified "openssl".  OpenSSL 3 adds a
	# Subject Key Identifier extension to these certificates by default, but
	# the H618 SBOOT parser treats every extension as an Allwinner ASCII-hex
	# key/hash field and aborts while parsing that binary SKI.  Use the exact
	# OpenSSL 1.1.1 binary bundled with the BSP, just like longan/build/pack.
	PATH="${BSP_OPENSSL_DIR}:${PATH}" dragonsecboot -toc1 \
		dragon_toc.cfg "${SECURE_KEYS}" "${SECURE_CNF}" version_base.mk
)
[[ -s "${secure_dir}/toc1.fex" ]] ||
	{ echo "ERROR: secure TOC1 was not generated" >&2; exit 1; }
grep -aFq 'boot_targets=fel mmc2 ' "${secure_dir}/toc1.fex" ||
	{ echo "ERROR: secure TOC1 does not contain the TX68 mmc2 boot target" >&2; exit 1; }
grep -aFq 'distro_bootcmd=' "${secure_dir}/toc1.fex" ||
	{ echo "ERROR: secure TOC1 does not contain distro_bootcmd" >&2; exit 1; }
openssl x509 -inform DER -in "${PACK_BASE}/toc1/cert/rootkey.der" \
	-pubkey -noout > "${work_dir}/android-rootkey.pub"
openssl x509 -inform DER -in "${secure_dir}/toc1/cert/rootkey.der" \
	-pubkey -noout > "${work_dir}/ubuntu-rootkey.pub"
cmp "${work_dir}/android-rootkey.pub" "${work_dir}/ubuntu-rootkey.pub" ||
	{ echo "ERROR: generated TOC1 root key differs from flashed m1k_go key" >&2; exit 1; }

# Public-key equality alone does not validate the Allwinner certificate
# extension layout.  Require each generated DER certificate to have the same
# size as its known-good Android counterpart and explicitly reject the SKI
# extension that makes H618 SBOOT fail in sunxi_bytes_merge().
secure_cert_names=(rootkey monitor optee u-boot vbmeta_a vbmeta_b)
for cert_name in "${secure_cert_names[@]}"; do
	android_cert="${PACK_BASE}/toc1/cert/${cert_name}.der"
	ubuntu_cert="${secure_dir}/toc1/cert/${cert_name}.der"
	[[ -s "${android_cert}" && -s "${ubuntu_cert}" ]] ||
		{ echo "ERROR: missing secure certificate: ${cert_name}" >&2; exit 1; }
	[[ "$(stat -c %s "${ubuntu_cert}")" -eq "$(stat -c %s "${android_cert}")" ]] ||
		{ echo "ERROR: ${cert_name}.der layout differs from known-good Android certificate" >&2; exit 1; }
	if openssl x509 -inform DER -in "${ubuntu_cert}" -noout -text |
		grep -Fq 'X509v3 Subject Key Identifier'; then
		echo "ERROR: ${cert_name}.der contains an H618-incompatible Subject Key Identifier" >&2
		exit 1
	fi
done
cp "${secure_dir}/toc1.fex" "${pack_dir}/toc1.fex"

cmp "${pack_dir}/u-boot.fex" "${PACK_BASE}/u-boot.fex" ||
	{ echo "ERROR: PhoenixSuit FES2 U-Boot is not the known-good Android burn tool" >&2; exit 1; }

# Boot0 owns DDR initialization and the first eMMC read.  Keep it byte-for-byte
# from the known-good Android m1k_go pack instead of using the Orange Pi Boot0
# executable from an older U-Boot package.
android_boot0="${PACK_BASE}/boot0_sdcard.fex"
[[ "$(stat -c %s "${android_boot0}")" -eq 61440 ]] ||
	{ echo "ERROR: unexpected m1k_go Boot0 size: ${android_boot0}" >&2; exit 1; }
[[ "$(dd if="${android_boot0}" bs=1 skip=4 count=8 status=none)" == "eGON.BT0" ]] ||
	{ echo "ERROR: invalid m1k_go Boot0 magic: ${android_boot0}" >&2; exit 1; }
cmp -n 128 -i 56:56 "${android_boot0}" "${PACK_BASE}/fes1.fex" ||
	{ echo "ERROR: m1k_go Boot0 and FES1 primary DDR profiles differ" >&2; exit 1; }
cp "${android_boot0}" "${pack_dir}/boot0_sdcard.fex"

cp "${SRC}/phoenix-config/tx68-image.cfg" "${pack_dir}/image.cfg"
cp "${SRC}/phoenix-config/tx68-sys_partition.fex.in" "${pack_dir}/sys_partition.fex"
sed -i "s/@ROOTFS_SECTORS@/${rootfs_sectors}/" "${pack_dir}/sys_partition.fex"
sed -i "s|TX68_PHOENIX_OUTPUT.img|$(basename "${OUTPUT_IMAGE}")|" "${pack_dir}/image.cfg"

rootfs_raw="${work_dir}/rootfs.raw"
echo "Extracting Ubuntu ext4 partition (${partition_sectors} sectors)"
dd if="${RAW_IMAGE}" of="${rootfs_raw}" bs=1M \
	skip="$((partition_start / 2048))" count="$((partition_sectors / 2048))" \
	status=progress

# The vendor U-Boot in this pack (u-boot/v2018.05-h618/.config) is CONFIG_ARM=y,
# not CONFIG_ARM64: it only has CONFIG_CMD_BOOTD/BOOTM/BOOTZ, no booti
# (CONFIG_CMD_BOOTI `depends on ARM64 || RISCV`, neither true here). A raw
# mainline arm64 Image cannot be booted with `booti` on this bootloader.
# arch/arm/lib/bootm.c does support jumping to an AArch64 kernel from bootm,
# gated on the legacy uImage header's IH_ARCH_ARM64 tag -- the same
# mechanism the working vendor 5.4 image already relies on. So if the rootfs
# carries a raw /boot/Image (armbian-build's layout; the vendor 5.4 kernel
# instead produces its own /boot/uImage directly and has no /boot/Image at
# all), wrap it into a uImage here rather than expecting U-Boot to boot it
# directly.
if debugfs -R "stat /boot/Image" "${rootfs_raw}" 2>/dev/null | grep -q "Inode:"; then
	echo "Wrapping mainline /boot/Image into a legacy uImage (this U-Boot has no booti, needs bootm)"
	raw_kernel="${work_dir}/Image"
	wrapped_kernel="${work_dir}/uImage"
	# armbian-build's /boot/Image is a symlink (-> vmlinuz-<release>). ext4
	# stores short symlink targets as a "fast symlink" with no data blocks at
	# all, so `debugfs dump` on the symlink path itself fails with "short
	# read" -- resolve it to the real file first.
	image_target="$(debugfs -R "stat /boot/Image" "${rootfs_raw}" 2>/dev/null |
		sed -n 's/^Fast link dest: "\(.*\)"$/\1/p')"
	image_path="/boot/Image"
	[[ -n "${image_target}" ]] && image_path="/boot/${image_target}"
	debugfs -R "dump ${image_path} ${raw_kernel}" "${rootfs_raw}" >/dev/null
	[[ -s "${raw_kernel}" ]] ||
		{ echo "ERROR: failed to extract ${image_path} from rootfs" >&2; exit 1; }
	# arm64 Image is entered at its load address (TEXT_OFFSET is 0 in every
	# kernel built since Linux 4.6); kernel_addr_r here matches
	# boot-tx68-next.cmd's setenv, which is 2 MiB aligned as arm64 Image requires.
	#
	# -A arm, NOT -A arm64. Confirmed on real hardware: this exact vendor
	# U-Boot (v2018.05-h618, CONFIG_ARM=y, no CONFIG_ARM64) rejected an
	# arm64-tagged uImage outright -- "Unsupported Architecture 0x16"
	# (0x16 = 22 = IH_ARCH_ARM64). Traced to include/image.h's
	# image_check_target_arch(), which checks against IH_ARCH_DEFAULT;
	# arch/arm/include/asm/u-boot.h defines IH_ARCH_DEFAULT as IH_ARCH_ARM
	# whenever CONFIG_ARM64 is unset. Only an ARM-tagged image passes that
	# gate here. The tag is only a header/validation field -- the actual
	# AArch32-to-AArch64 execution-state switch for the real jump happens
	# through this vendor tree's sunxi_board.c (an SMC round-trip through
	# BL31/EL3, the same mechanism that already boots the working vendor
	# 5.4 aarch64 kernel via bootm), so tagging it "arm" here does not
	# change how the kernel actually runs once entered.
	mkimage -A arm -O linux -T kernel -C none \
		-a 0x41000000 -e 0x41000000 \
		-n "TX68 mainline Linux (armbian-build)" \
		-d "${raw_kernel}" "${wrapped_kernel}" >/dev/null
	debugfs -w -R "rm /boot/uImage" "${rootfs_raw}" >/dev/null 2>&1 || true
	debugfs -w -R "write ${wrapped_kernel} /boot/uImage" "${rootfs_raw}" >/dev/null
	rm -f "${raw_kernel}" "${wrapped_kernel}"

	# armbian-build's own postinst already wraps /boot/initrd.img-<release>
	# into /boot/uInitrd via mkimage -- but with the standard mainline tag
	# (-A arm64, matching the kernel's own arch), which hits the exact same
	# image_check_target_arch() rejection as the kernel did, just for the
	# ramdisk this time: confirmed on real hardware, "No Linux ARM Ramdisk
	# Image / Ramdisk image is corrupt or invalid" right after the kernel
	# itself booted successfully with the arm-tagged uImage above. Re-wrap
	# the same raw initrd with -A arm for the same reason as the kernel.
	echo "Re-wrapping /boot/uInitrd with -A arm (same IH_ARCH_DEFAULT gate as the kernel)"
	raw_initrd="${work_dir}/initrd.img"
	wrapped_initrd="${work_dir}/uInitrd"
	initrd_target="$(debugfs -R "stat /boot/initrd.img" "${rootfs_raw}" 2>/dev/null |
		sed -n 's/^Fast link dest: "\(.*\)"$/\1/p')"
	initrd_path="/boot/initrd.img"
	[[ -n "${initrd_target}" ]] && initrd_path="/boot/${initrd_target}"
	debugfs -R "dump ${initrd_path} ${raw_initrd}" "${rootfs_raw}" >/dev/null
	[[ -s "${raw_initrd}" ]] ||
		{ echo "ERROR: failed to extract ${initrd_path} from rootfs" >&2; exit 1; }
	# Debian/Ubuntu's update-initramfs defaults to gzip; detect it from the
	# magic bytes rather than assuming, so a future compression setting
	# change doesn't silently produce a bad ramdisk tag.
	initrd_magic="$(dd if="${raw_initrd}" bs=1 count=2 status=none | xxd -p)"
	case "${initrd_magic}" in
		1f8b) initrd_comp=gzip ;;
		28b5) initrd_comp=zstd ;;
		fd37) initrd_comp=lzma ;;
		*) echo "ERROR: unrecognized initrd compression magic 0x${initrd_magic}" >&2; exit 1 ;;
	esac
	mkimage -A arm -O linux -T ramdisk -C "${initrd_comp}" \
		-a 0 -e 0 -n uInitrd \
		-d "${raw_initrd}" "${wrapped_initrd}" >/dev/null
	debugfs -w -R "rm /boot/uInitrd" "${rootfs_raw}" >/dev/null 2>&1 || true
	debugfs -w -R "write ${wrapped_initrd} /boot/uInitrd" "${rootfs_raw}" >/dev/null
	rm -f "${raw_initrd}" "${wrapped_initrd}"
fi

echo "Installing current TX68 boot script into extracted rootfs"
boot_cmd="${TX68_BOOT_CMD:-${SRC}/bootscripts/boot-tx68.cmd}"
[[ -f "${boot_cmd}" ]] ||
	{ echo "ERROR: TX68_BOOT_CMD not found: ${boot_cmd}" >&2; exit 1; }
boot_scr="${work_dir}/boot.scr"
mkimage -C none -A arm -T script -d "${boot_cmd}" "${boot_scr}" >/dev/null
debugfs -w -R "rm /boot/boot.cmd" "${rootfs_raw}" >/dev/null
debugfs -w -R "write ${boot_cmd} /boot/boot.cmd" "${rootfs_raw}" >/dev/null
debugfs -w -R "rm /boot/boot.scr" "${rootfs_raw}" >/dev/null
debugfs -w -R "write ${boot_scr} /boot/boot.scr" "${rootfs_raw}" >/dev/null

echo "Checking extracted ext4 filesystem"
e2fsck -fn "${rootfs_raw}"

echo "Converting rootfs to Android sparse format"
"${TOOLS}/android/img2simg" "${rootfs_raw}" "${pack_dir}/rootfs.fex"

echo "Validating sparse rootfs round trip"
rootfs_roundtrip="${work_dir}/rootfs.roundtrip"
"${TOOLS}/android/simg2img" "${pack_dir}/rootfs.fex" "${rootfs_roundtrip}"
cmp "${rootfs_raw}" "${rootfs_roundtrip}"
rm -f "${rootfs_roundtrip}" "${rootfs_raw}"

(
	cd "${pack_dir}"
	busybox unix2dos sys_partition.fex >/dev/null
	"${TOOLS}/mod_update/script" sys_partition.fex >/dev/null
	"${TOOLS}/mod_update/update_mbr" sys_partition.bin 4 >/dev/null
	"${TOOLS}/mod_update/update_mbr" \
		sys_partition.bin 4 sunxi_mbr.fex dlinfo.fex \
		"${emmc_sectors}" "${logical_start}" 0 >/dev/null

	"${TOOLS}/eDragonEx/dragon" image.cfg sys_partition.fex
)

generated_image="${pack_dir}/$(basename "${OUTPUT_IMAGE}")"
[[ -s "${generated_image}" ]] ||
	{ echo "ERROR: PhoenixSuit image was not generated" >&2; exit 1; }

magic="$(dd if="${generated_image}" bs=8 count=1 status=none)"
[[ "${magic}" == "IMAGEWTY" ]] ||
	{ echo "ERROR: invalid PhoenixSuit image magic: ${magic}" >&2; exit 1; }

echo "Validating embedded FEL/FES boot chain and rootfs"
(
	cd "${pack_dir}"
	# parser_img only accepts paths relative to its current working directory.
	"${TOOLS}/mod_update/parser_img" \
		"$(basename "${generated_image}")" "parsed-fes1.fex" \
		"FES     " "FES_1-0000000000" >/dev/null
	"${TOOLS}/mod_update/parser_img" \
		"$(basename "${generated_image}")" "parsed-fes2-uboot.fex" \
		"12345678" "UBOOT_0000000000" >/dev/null
	"${TOOLS}/mod_update/parser_img" \
		"$(basename "${generated_image}")" "parsed-boot0.fex" \
		"12345678" "1234567890BOOT_0" >/dev/null
	"${TOOLS}/mod_update/parser_img" \
		"$(basename "${generated_image}")" "parsed-boot-package.fex" \
		"12345678" "BOOTPKG-00000000" >/dev/null
	"${TOOLS}/mod_update/parser_img" \
		"$(basename "${generated_image}")" "parsed-toc1.fex" \
		"12345678" "TOC1_00000000000" >/dev/null
	"${TOOLS}/mod_update/parser_img" \
		"$(basename "${generated_image}")" "parsed-rootfs.fex" \
		"RFSFAT16" "ROOTFS_FEX000000" >/dev/null
	cmp fes1.fex parsed-fes1.fex
	cmp u-boot.fex parsed-fes2-uboot.fex
	cmp boot0_sdcard.fex parsed-boot0.fex
	cmp boot_package.fex parsed-boot-package.fex
	cmp toc1.fex parsed-toc1.fex
	cmp rootfs.fex parsed-rootfs.fex
)

mv "${generated_image}" "${OUTPUT_IMAGE}"
sha256sum "${OUTPUT_IMAGE}" | tee "${OUTPUT_IMAGE}.sha256"

cat <<EOF
PhoenixSuit image ready:
  ${OUTPUT_IMAGE}

Source:
  ${RAW_IMAGE}
Rootfs partition:
  source=${partition_sectors} sectors, phoenix=${rootfs_sectors} sectors
EOF
