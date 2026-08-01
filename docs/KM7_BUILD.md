# Build KM7 images

Run the one-command build from the repository root:

```bash
cd /media/jimmy/WORK/AOSP/build
./km7/build-emmc.sh
```

The script builds the proven KM7 configuration:

- Ubuntu 24.04 Noble
- Khadas legacy kernel 5.15
- GNOME desktop, `mid` tier
- KM7 S4/AP222 signed U-Boot

Successful builds produce both files in `output/images/`:

| File suffix | Purpose |
|---|---|
| `_desktop.img` | Raw disk image for SD card or `dd` |
| `_desktop.emmc.img` | Amlogic v2 package for USB Burning Tool and eMMC |

For eMMC, select only the `.emmc.img` file in Amlogic USB Burning Tool. The
regular `.img` is not a Burn Tool package. Flashing eMMC erases the installed
system, so keep a known-good recovery image first.

## Flash eMMC from Linux (no Windows VM)

The verified Linux tool checkout is:

```text
/media/jimmy/WORK/AOSP/TOOLS/khadas-utils
```

Install it once if `burn-tool` is not already available:

```bash
cd /media/jimmy/WORK/AOSP/TOOLS/khadas-utils
sudo ./INSTALL
```

Put KM7 into Amlogic USB Burning mode, then flash the generated package. After
a newer build, replace the filename below with the path printed by
`./km7/build-emmc.sh`:

```bash
burn-tool -v aml -b VIM1S -i \
  '/media/jimmy/WORK/AOSP/build/output/images/Armbian-unofficial_26.08.0-trunk_Km7_noble_legacy_5.15.137_gnome_desktop.emmc.img'
```

`-b VIM1S` is intentional even though the device is KM7. In `khadas-utils` it
selects the Amlogic **S4** backend and runs `adnl_burn_pkg`; it does not replace
the KM7 DTB or signed KM7 bootloader stored inside the image.

The command performs a full flash erase by default, so do not disconnect USB
or power while the percentage is moving. A completed run must reach 100% and
print `Done!`; afterward, disconnect the burning cable and cold-boot the box.

Observed on the real KM7 on 2026-08-01: Linux detected the Amlogic device,
accepted the generated `.emmc.img`, and started transferring it (`6%` seen).
Final flash completion and the first Armbian boot are still pending validation.

If the device does not enumerate, use UART at 921600 baud and enter burning
mode from the `km7#` prompt:

```text
run usb_burning
```

This Linux workflow replaces the Windows Amlogic USB Burning Tool/VMware path
once the completed flash and cold boot have passed on real hardware.

The equivalent manual command is:

```bash
./compile.sh \
  BOARD=km7 \
  BRANCH=legacy \
  RELEASE=noble \
  BUILD_DESKTOP=yes \
  DESKTOP_TIER=mid \
  DESKTOP_ENVIRONMENT=gnome \
  KERNEL_CONFIGURE=no
```

The KM7 board automatically enables `extensions/km7-amlogic-burn.sh`, which
creates and validates the additional `.emmc.img` package. The wrapper also
checks the generated SHA256 files before reporting success.
