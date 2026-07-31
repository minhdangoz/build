#!/usr/bin/env bash

set -euo pipefail

usage()
{
	cat <<'EOF'
Usage:
  tx68/scripts/tx68-build-uboot.sh [OUTPUT_DEB]

Builds the TX68 vendor U-Boot (v2018.05-h618) with the TX68 patches applied,
wraps it in the Allwinner "uboot" container, and emits a .deb in the layout
tx68-build-phoenix-image.sh expects (u-boot.fex + boot_package.fex).

TX68 cannot use mainline U-Boot: its BL31 hands off in AArch32 (spsr 0x1d3,
see docs/SECURE_BOOT.md) and every vendor sun50iw9 defconfig is 32-bit ARM.
So the vendor tree is what gets patched.

Environment:
  TX68_UBOOT_SRC   Pristine vendor U-Boot tree to copy from
                   (default: /media/jimmy/WORK/AOSP/orangepi-build/u-boot/v2018.05-h618).
                   It is only ever read; the build happens in TX68_UBOOT_WORK.
  TX68_UBOOT_WORK  Scratch build tree (default: ../tx68-uboot-build next to
                   this armbian-build checkout). Wiped and recreated each run.
  TX68_BOOTDELAY   Seconds to wait at "Hit any key to stop autoboot"
                   (default: 3). The vendor default of 1 is too short to
                   actually interrupt over serial.
  TX68_BASE_DEB    Existing TX68 U-Boot .deb to take boot_package.fex and the
                   packaging metadata from
                   (default: tx68/uboot-debs/linux-u-boot-next-tx68_0.1.0_arm64.deb).
EOF
}

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
	usage
	exit 0
fi
if [[ $# -gt 1 ]]; then
	usage >&2
	exit 2
fi

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UBOOT_SRC="${TX68_UBOOT_SRC:-/media/jimmy/WORK/AOSP/orangepi-build/u-boot/v2018.05-h618}"
WORK="${TX68_UBOOT_WORK:-$(cd "${SRC}/../.." && pwd)/tx68-uboot-build}"
BOOTDELAY="${TX68_BOOTDELAY:-3}"
BASE_DEB="${TX68_BASE_DEB:-${SRC}/uboot-debs/linux-u-boot-next-tx68_0.1.0_arm64.deb}"
OUTPUT_DEB="${1:-${SRC}/uboot-debs/linux-u-boot-next-tx68-fdtfix_0.1.0_arm64.deb}"

TOOLS="${SRC}/pack-uboot/tools"
SYS_CONFIG="${SRC}/pack-uboot/bin/sys_config/sys_config_tx68.fex"

# The vendor tree is a 32-bit ARM U-Boot -- see docs/SECURE_BOOT.md.
CROSS="arm-linux-gnueabi-"

required_commands=(rsync patch make dpkg-deb python3 sed "${CROSS}gcc")
for command_name in "${required_commands[@]}"; do
	command -v "${command_name}" >/dev/null ||
		{ echo "ERROR: missing host command: ${command_name}" >&2; exit 1; }
done

[[ -d "${UBOOT_SRC}" ]] ||
	{ echo "ERROR: vendor U-Boot source not found: ${UBOOT_SRC}" >&2; exit 1; }
[[ -f "${UBOOT_SRC}/.config" ]] ||
	{ echo "ERROR: vendor U-Boot tree has no prebuilt .config: ${UBOOT_SRC}" >&2; exit 1; }
[[ -f "${BASE_DEB}" ]] ||
	{ echo "ERROR: base U-Boot deb not found: ${BASE_DEB}" >&2; exit 1; }
[[ -x "${TOOLS}/update_uboot" && -x "${TOOLS}/script" ]] ||
	{ echo "ERROR: pack-uboot tools missing under ${TOOLS}" >&2; exit 1; }
[[ -f "${SYS_CONFIG}" ]] ||
	{ echo "ERROR: sys_config not found: ${SYS_CONFIG}" >&2; exit 1; }

echo "Copying vendor U-Boot to a writable tree: ${WORK}"
rm -rf -- "${WORK}"
mkdir -p "${WORK}"
# The upstream checkout is root-owned and must stay pristine; build on a copy.
rsync -a --exclude='.git' "${UBOOT_SRC}/" "${WORK}/"
chmod -R u+w "${WORK}"

# 0001 is already reflected in the tree's shipped .config
# (CONFIG_ENV_FAT_DEVICE_AND_PART="2:auto"); 0002 and 0003 are the ones that
# make a mainline kernel bootable. Applying an already-applied patch is a hard
# error rather than a silent skip, so each is checked first.
for patch_file in "${SRC}"/patches/000[23]-*.patch; do
	[[ -f "${patch_file}" ]] || continue
	if patch -p1 -d "${WORK}" --dry-run --silent < "${patch_file}" >/dev/null 2>&1; then
		echo "Applying $(basename "${patch_file}")"
		patch -p1 -d "${WORK}" --silent < "${patch_file}"
	else
		echo "ERROR: $(basename "${patch_file}") does not apply cleanly" >&2
		exit 1
	fi
done

# The vendor default of 1 second cannot realistically be hit over serial.
sed -i "s/^CONFIG_BOOTDELAY=.*/CONFIG_BOOTDELAY=${BOOTDELAY}/" "${WORK}/.config"
grep -q "^CONFIG_BOOTDELAY=${BOOTDELAY}$" "${WORK}/.config" ||
	{ echo "ERROR: failed to set CONFIG_BOOTDELAY" >&2; exit 1; }

# 2018-era source vs modern GCC: these warnings are fatal by default here
# (Makefile adds -Werror), and none of them are actionable in vendor code.
KCFLAGS="-fcommon -Wno-error -Wno-attributes -Wno-array-bounds"
KCFLAGS+=" -Wno-maybe-uninitialized -Wno-stringop-overflow"
KCFLAGS+=" -Wno-stringop-truncation -Wno-address-of-packed-member"
KCFLAGS+=" -Wno-implicit-fallthrough"

echo "Building U-Boot (${CROSS%-})"
make -C "${WORK}" CROSS_COMPILE="${CROSS}" KCFLAGS="${KCFLAGS}" -j"$(nproc)" > "${WORK}/build.log" 2>&1 ||
	{ echo "ERROR: U-Boot build failed, see ${WORK}/build.log" >&2; exit 1; }
[[ -s "${WORK}/u-boot.bin" ]] ||
	{ echo "ERROR: u-boot.bin was not produced" >&2; exit 1; }

# Prove both fixes are really in the object code rather than trusting that the
# patches applied -- a silently-unpatched U-Boot looks identical from outside
# and costs a full flash cycle to discover.
# Read each object's relocations into a variable first: piping objdump into
# `grep -q` makes grep exit on the first match, objdump take SIGPIPE, and
# `set -o pipefail` then report the whole pipeline as failed even though the
# symbol was found.
bootm_relocs="$("${CROSS}objdump" -r "${WORK}/common/bootm.o")"
grep -q "boot_get_fdt" <<< "${bootm_relocs}" ||
	{ echo "ERROR: bootm.o does not reference boot_get_fdt (0002 not effective)" >&2; exit 1; }
image_fdt_relocs="$("${CROSS}objdump" -r "${WORK}/common/image-fdt.o")"
grep -q "fdt_open_into" <<< "${image_fdt_relocs}" ||
	{ echo "ERROR: image-fdt.o does not reference fdt_open_into (0003 not effective)" >&2; exit 1; }
grep -q "fdt_fixup_memory_banks" <<< "${image_fdt_relocs}" ||
	{ echo "ERROR: image-fdt.o does not reference fdt_fixup_memory_banks (0003 incomplete)" >&2; exit 1; }

# The /memory fixup is the difference between a booting kernel and an instant
# "Failed to allocate page table page" panic, and arch_fixup_fdt() also has a
# __weak stub in this very file -- so a relocation check alone cannot tell a
# patched build from an unpatched one. Look for strings only the patch emits.
uboot_strings="$(strings "${WORK}/u-boot.bin")"
for marker in "Linux /memory:" "memory fixup failed" "failed to grow fdt"; do
	grep -qF "${marker}" <<< "${uboot_strings}" ||
		{ echo "ERROR: built u-boot.bin lacks \"${marker}\" -- patches incomplete" >&2; exit 1; }
done

echo "Wrapping u-boot.bin into the Allwinner uboot container"
pack_dir="${WORK}/pack"
rm -rf -- "${pack_dir}"
mkdir -p "${pack_dir}"
cp "${WORK}/u-boot.bin" "${pack_dir}/u-boot.fex"
cp "${SYS_CONFIG}" "${pack_dir}/sys_config.fex"
# The vendor tools parse sys_config as CRLF and read paths relative to $PWD.
sed -i 's/$/\r/' "${pack_dir}/sys_config.fex"
tools_abs="$(readlink -f "${TOOLS}")"
(
	cd "${pack_dir}"
	"${tools_abs}/script" sys_config.fex > /dev/null
	"${tools_abs}/update_uboot" -no_merge u-boot.fex sys_config.bin > /dev/null
)
[[ "$(stat -c %s "${pack_dir}/u-boot.fex")" -eq 786432 ]] ||
	{ echo "ERROR: wrapped u-boot.fex is not the expected 786432 bytes" >&2; exit 1; }

echo "Building ${OUTPUT_DEB}"
deb_dir="${WORK}/deb"
rm -rf -- "${deb_dir}"
mkdir -p "${deb_dir}"
dpkg-deb -R "${BASE_DEB}" "${deb_dir}"

base_stem="$(basename "${BASE_DEB}" _arm64.deb)"
out_stem="$(basename "${OUTPUT_DEB}" _arm64.deb)"
mv "${deb_dir}/usr/lib/${base_stem}_arm64" "${deb_dir}/usr/lib/${out_stem}_arm64"
payload="${deb_dir}/usr/lib/${out_stem}_arm64"
sed -i "s/^Package: .*/Package: ${out_stem%_*}/" "${deb_dir}/DEBIAN/control"

# boot_package.fex is a "sunxi-package" container; splice the new U-Boot over
# the old one in place. The wrapped size is fixed at 786432 bytes, so the item
# table needs no rewriting.
python3 - "${payload}/boot_package.fex" "${pack_dir}/u-boot.fex" <<'PYEOF'
import struct
import sys

package_path, uboot_path = sys.argv[1], sys.argv[2]
uboot = open(uboot_path, 'rb').read()
data = bytearray(open(package_path, 'rb').read())

if bytes(data[:13]) != b'sunxi-package':
    sys.exit('boot_package.fex is not a sunxi-package container')

count = struct.unpack_from('<I', data, 0x20)[0]
ITEM_BASE, ITEM_STRIDE, ITEM_OFFSET_LEN = 0x3C, 0x170, 0x44

for index in range(count):
    item = ITEM_BASE + index * ITEM_STRIDE
    name = data[item + 4:item + 68].split(b'\0')[0].decode()
    offset, length = struct.unpack_from('<II', data, item + ITEM_OFFSET_LEN)
    if name == 'u-boot':
        if length != len(uboot):
            sys.exit(f'u-boot item is {length} bytes, new image is {len(uboot)}')
        data[offset:offset + length] = uboot
        open(package_path, 'wb').write(bytes(data))
        print(f'  spliced u-boot at 0x{offset:x} ({length} bytes)')
        break
else:
    sys.exit('no u-boot item found in boot_package.fex')
PYEOF

cp "${pack_dir}/u-boot.fex" "${payload}/u-boot.fex"
rm -f -- "${OUTPUT_DEB}"
dpkg-deb -b "${deb_dir}" "${OUTPUT_DEB}" > /dev/null

cat <<EOF

TX68 U-Boot package ready:
  ${OUTPUT_DEB}

Build tree kept for inspection:
  ${WORK}

Pass it to the image packer with:
  TX68_UBOOT_DEB=${OUTPUT_DEB}
EOF
