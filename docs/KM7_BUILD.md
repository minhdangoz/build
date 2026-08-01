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
