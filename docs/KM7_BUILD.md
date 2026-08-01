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

Put KM7 into Amlogic USB Burning mode and confirm the target USB serial:

```bash
lsusb -v -d 1b8e:c004 2>/dev/null | grep -E 'iProduct|iSerial'
```

Flash the generated package with the target serial selected explicitly. After
a newer build, replace the image filename below with the path printed by
`./km7/build-emmc.sh`, and replace the sample serial with the `iSerial` value
reported for the connected KM7:

```bash
cd /media/jimmy/WORK/AOSP/TOOLS/khadas-utils

./aml-flash-tool/tools/adnl/adnl_burn_pkg \
  -s '001671190592071700000000' \
  -p '/media/jimmy/WORK/AOSP/build/output/images/Armbian-unofficial_26.08.0-trunk_Km7_noble_legacy_5.15.137_gnome_desktop.emmc.img' \
  -e 1 \
  -r 1
```

These are the standard KM7 full-flash settings used by this guide:

- `-s <serial>` selects the intended Amlogic DNL device. This matters when
  more than one Amlogic device is connected.
- `-e 1` erases the whole eMMC before writing the package.
- `-r 1` automatically reboots the KM7 after a successful flash.

Do not disconnect USB or power while the percentage is moving. A completed
run must reach 100%, verify the package, print `burn successful^_^`, and then
reboot the device automatically. If the board remains in DNL mode despite a
successful result, disconnect both power and the OTG cable, wait a few
seconds, and cold-boot it.

The higher-level equivalent is `aml-burn-tool -b VIM1S -i <image> -r`:
`VIM1S` selects the Amlogic **S4** ADNL backend, the wrapper maps its default
full erase to `-e 1`, and `-r` maps to ADNL `-r 1`. The top-level `burn-tool`
does not currently forward the reboot option, so it is not the recommended
command for this workflow.

Observed on the real KM7 on 2026-08-01: Linux detected the Amlogic device and
successfully flashed and verified the generated `.emmc.img`. `burn-tool`
printed `burn successful^_^` and `Done!`. The first successful Armbian boot is
still pending validation after the boot-script fix below.

### U-Boot finds `boot.scr`, then falls back to PXE

If UART contains all of these messages:

```text
Scanning mmc 1:3...
Found U-Boot script /boot/boot.scr
Unknown command 'setexpr'
Bad Linux ARM64 Image magic!
BOOTP broadcast 1
```

the flash succeeded and this is not a `burn-tool` failure. U-Boot found the
root filesystem on eMMC partition 3, but the old KM7 boot script omitted
`:${distro_bootpart}` when loading `armbianEnv.txt`, the DTB, `Image`, and
`Initrd`. Those reads therefore targeted the wrong partition and PXE was only
the final fallback.

The fix is owned by:

- `config/bootscripts/boot-meson-s4t7.cmd`: every filesystem command uses
  `${devnum}:${distro_bootpart}`.
- the KM7 U-Boot config: `CONFIG_CMD_SETEXPR=y`.

After rebuilding and flashing, UART should progress from finding `boot.scr` to
loading the environment, `km7.dtb`, `Image`, and `Initrd`, then print
`Starting kernel ...`. It must not print `Bad Linux ARM64 Image magic!`.

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
