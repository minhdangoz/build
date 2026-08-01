# Build KM7 (Amlogic S905Y4 / S4 / AP222)

This is the build and verification guide for the Mecool KM7 TV box. Hardware
facts live in [`docs/KM7_HARDWARE_SPECS.md`](../docs/KM7_HARDWARE_SPECS.md);
the original Fenix bring-up evidence and recovery story live in
[`docs/KM7_S905Y4_BRINGUP_AND_RECOVERY.md`](../docs/KM7_S905Y4_BRINGUP_AND_RECOVERY.md).

> KM7 and Khadas VIM1S share the S905Y4/S4 silicon and Khadas 5.15 kernel
> family. They do not share DRAM, board wiring, radio or recovery-key behavior.
> Never boot KM7 with the VIM1S DTB or VIM1S U-Boot target.

## What this repo owns

| Layer | KM7 owner path |
|---|---|
| Board profile | `config/boards/km7.csc` |
| Kernel family | `config/sources/families/meson-s4t7.conf` |
| Kernel + common-drivers changes | `patch/kernel/archive/meson-s4t7-5.15-km7/` |
| U-Boot/AP222/DDR3 changes | `patch/u-boot/u-boot-meson-s4t7-km7/` |
| Initramfs/runtime modules, W1 RF data, FD650 service | `packages/bsp/meson-s4t7/km7/` plus the VIM1S S4 module-list base selected by the board hook |
| Reference implementation | `/media/jimmy/WORK/AOSP/fenix` (read-only) |
| Android hardware reference | `/media/jimmy/WORK/AOSP/s905y4` (read-only) |

The target stays on Khadas's `khadas-vims-5.15.y` vendor kernel. Moving KM7
from Fenix into this repo removes the second build framework; it does not turn
S905Y4 into a mainline-kernel board.

## Build

```bash
cd /media/jimmy/WORK/AOSP/build
./compile.sh \
  BOARD=km7 \
  BRANCH=legacy \
  RELEASE=noble \
  BUILD_DESKTOP=yes \
  DESKTOP_ENVIRONMENT=xfce \
  KERNEL_CONFIGURE=no
```

Do not run `compile.sh` with `sudo`; Armbian requests privilege when needed.
The result is written under `output/images/`.

The first safe target is an SD image. Do not overwrite eMMC boot firmware until
the SD image has passed the acceptance checks below and both UART recovery and
the physical SARADC recovery key have been tested.

## Boot chain

```text
Amlogic BootROM
  -> signed S4/AP222 BL2 + DDR3 firmware
  -> BL31 / secure firmware
  -> KM7 U-Boot 2019.01
  -> Image + amlogic/km7.dtb + Initrd
  -> Ubuntu root filesystem
```

Important board-specific behavior carried by the U-Boot patches:

- `km7_defconfig`, AP222 BL30 selection and DDR3 timing; VIM1S uses LPDDR4.
- `fdtfile=amlogic/km7.dtb`.
- HPD/EDID failure falls back to `1080p60hz` instead of passing
  `vout=none hdmimode=none` to Linux.
- The physical recovery path uses SARADC channel 0, range 0..50.
- UART recovery remains available through `run usb_burning` / `adnl 1200`.

Serial console:

```bash
tio -b 921600 /dev/ttyUSB0
```

## Hardware traps already proven on KM7

- eMMC needs modular `amlogic-mmc.ko` and its provider chain in initramfs.
  The board reuses the maintained VIM1S/S4 initramfs list, not the VIM1S DTB.
- WiFi is Amlogic W1 (`0x8888:0x8888` on seven SDIO functions), not Broadcom.
  The board disables the family's Broadcom `hciattach`, installs the ported W1
  driver and RF tables, and loads `aml_sdio` before `vlsicomm`.
- GPIOX_16 is the W1 32.768 kHz clock. `pwm_ef` must not claim the pin before
  `aml_wifi`.
- FD650 uses GPIOD_6/GPIOD_7. I2C1 cannot own those same pins. The front-panel
  service is required because the driver does not power the display until its
  sysfs interface receives a write.
- eMMC stays capped at 100 MHz. Do not raise it without repeated hardware tests.
- The normal Linux USB controller is host-only; the USB Burning gadget is a
  separate U-Boot recovery path.
- DVB/tuner nodes are disabled because the observed unit does not populate them.

## GPU and video are separate acceptance items

The default `panfrost` overlay replaces the vendor GPU compatible with
`arm,mali-bifrost`, which matches the in-tree Panfrost driver. That makes the
binding plausible, not proven. Verify the actual image:

```bash
glxinfo -B | grep -E 'OpenGL renderer|OpenGL version'
dmesg | grep -Ei 'panfrost|mali|gpu'
```

`llvmpipe` means GPU acceleration failed.

VPU decode has a different driver/firmware/userspace path. While a supported
clip plays:

```bash
ls -l /lib/firmware/video/video_ucode.bin
lsmod | grep -E 'amvdec|decoder_common|stream_input|media_clock'
cat /sys/class/vdec/vdec_status
gst-inspect-1.0 | grep -i aml
```

An active decoder in `vdec_status` is the decisive VPU proof.

## Pre-flash acceptance

- Build exits zero and the artifact has a unique name and recorded checksum.
- The image contains `amlogic/km7.dtb`; it does not select `kvim1s.dtb`.
- `amlogic-mmc.ko` and `cqhci.ko` are present in the generated initramfs.
- W1 modules and `/vendor/etc/wifi/w1/aml_wifi_rf*.txt` are present.
- Root filesystem passes `e2fsck -fn`.
- UART reaches the `km7#` prompt and then Linux at 921600 baud.
- HDMI boots with a valid mode across at least five cold boots.
- Ethernet, both USB-A ports, eMMC, SD, WiFi, FD650 and audio are tested.
- GPU renderer and VPU decode are verified separately.
- `run usb_burning` enumerates an Amlogic USB device on the host.
- The physical SARADC recovery key enters USB Burning mode.
- A known-good Android factory image is available before touching eMMC.

## Not yet claimed

The Fenix reference proves the board wiring, eMMC boot, HDMI fallback, VPU
module/microcode path and FD650 pinmux fixes. The first image from this repo
still needs real-hardware proof for the combined Armbian packaging, Panfrost
renderer, W1 association and Bluetooth HCI behavior. Keep those as unknowns
until UART/runtime evidence says otherwise.
