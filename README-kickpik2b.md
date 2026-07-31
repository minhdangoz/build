# KickPi K2B — Ubuntu Build & Flash

## Build

```bash
./compile.sh BOARD=kickpik2b BRANCH=current RELEASE=resolute \
  BUILD_MINIMAL=no BUILD_DESKTOP=yes DESKTOP_ENVIRONMENT=xfce DESKTOP_TIER=mid \
  KERNEL_CONFIGURE=no COMPRESS_OUTPUTIMAGE=sha,gz
```

- `RELEASE=resolute` — Ubuntu 26.04 LTS userspace
- `BRANCH=current` — kernel 6.18
- Swap `RELEASE`/`DESKTOP_ENVIRONMENT`/`DESKTOP_TIER` for other combos (e.g. `BUILD_DESKTOP=no` for a headless/server image).

Output lands in `output/images/Armbian-unofficial_*_Kickpik2b_resolute_current_*.img[.gz]` plus a `.sha` checksum.

## Flash

KickPi K2B (Allwinner H618) boots off a plain GPT/MBR disk image written directly to SD card or eMMC — it does **not** use Allwinner's legacy FEL/PhoenixSuit(LiveSuit)/openixsuit vendor tooling. Those tools are for older sun4i/sun7i chips with a proprietary boot0/eGON flow; this board uses mainline U-Boot SPL baked straight into the image, so a raw image writer is all you need.

1. If compressed, decompress: `gunzip output/images/*.img.gz`
2. Flash with any of:
   - **balenaEtcher** / **Raspberry Pi Imager** (GUI, easiest, verifies write)
   - `dd`:
     ```bash
     sudo dd if=output/images/Armbian-*.img of=/dev/sdX bs=4M status=progress conv=fsync
     sync
     ```
     Replace `/dev/sdX` with your actual SD card device (check with `lsblk` first — **not** a partition like `/dev/sdX1`).
3. Insert SD card into the K2B and power on.

For eMMC installs, boot from the SD card first, then use `armbian-install` (or `nand-sata-install`) on the running system to write to onboard eMMC.
