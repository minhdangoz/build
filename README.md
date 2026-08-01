<h3 align="center">
  <a href=#><img src="https://raw.githubusercontent.com/armbian/.github/master/profile/logosmall.png" alt="Armbian logo"></a>
  <br><br>
</h3>

## TX68 and KM7 build inventory

This fork is the single build project for the TX68 and KM7 TV boxes. The
authoritative machine-readable source inventory is
[`config/boards/tx68-km7-source-lock.inc`](config/boards/tx68-km7-source-lock.inc).
Board builds consume immutable commits and release checksums from repositories
owned by [`minhdangoz`](https://github.com/minhdangoz); they do not build from
moving upstream branches.

### Current OS and boot stack

| | TX68 | KM7 |
|---|---|---|
| Hardware | Allwinner H618, vendor board `m1k_go` | Amlogic S905Y4/S4, AP222, DDR3 |
| Armbian branch | `current` | `legacy` |
| Kernel class | Mainline-derived | Khadas vendor kernel |
| Kernel version | Linux **6.18.41** | Linux **5.15.137** |
| Kernel repository | [`minhdangoz/linux-stable`](https://github.com/minhdangoz/linux-stable) | [`minhdangoz/khadas-linux`](https://github.com/minhdangoz/khadas-linux) |
| Pinned kernel snapshot | [`457936105aed`](https://github.com/minhdangoz/linux-stable/commit/457936105aed97a31778991bff97e8a0346d1bff) | [`ebbf016784df`](https://github.com/minhdangoz/khadas-linux/commit/ebbf016784df1436c6bdf0118f816f69042dd675) |
| Extra kernel drivers | AIC8801 SDIO DKMS package | Khadas `common_drivers` snapshot [`fc43f888dfea`](https://github.com/minhdangoz/khadas-common-drivers/commit/fc43f888dfea51bcf5037623fd4b4683cd5fbf9a) |
| U-Boot version | Vendor **2018.05**, 32-bit | CoreELEC/Khadas **2019.01** |
| U-Boot repository | [`minhdangoz/tx68-u-boot`](https://github.com/minhdangoz/tx68-u-boot) | [`minhdangoz/coreelec-u-boot`](https://github.com/minhdangoz/coreelec-u-boot) |
| Pinned U-Boot snapshot | [`d7e300ad8182`](https://github.com/minhdangoz/tx68-u-boot/commit/d7e300ad8182b8fbd15f66bcb45c4e62ac23a3a2) | [`3a50f0ae9834`](https://github.com/minhdangoz/coreelec-u-boot/commit/3a50f0ae983426a44940223423aa348deb909dc9) |
| Default distribution | Ubuntu 24.04 Noble, GNOME/X11 | Ubuntu 24.04 Noble, GNOME/X11 |

`current` and `legacy` describe the kernel integration track, not image age:
TX68 follows the current mainline-derived sunxi64 kernel, while KM7 deliberately
stays on the vendor 5.15 tree because its S905Y4 multimedia, eMMC, W1 radio and
other board drivers are not supplied by an equivalent mainline stack here.

### Bootloader details

TX68 does **not** use the Armbian/mainline U-Boot artifact. Its secure boot path
is fixed by the hardware/vendor signing chain:

```text
Allwinner BootROM -> vendor Boot0 -> BL31 -> vendor U-Boot 2018.05 (AArch32)
                   -> Linux 6.18.41 + TX68 DTB + Ubuntu rootfs
```

The signed pack inputs and keys are stored only in the private
`minhdangoz/tx68-secure-pack` release, encrypted with `age`. Restore them on a
clean checkout with `./tx68/scripts/tx68-restore-secure-pack.sh`.

KM7 uses the signed Amlogic S4/AP222 boot flow:

```text
Amlogic BootROM -> signed BL2 + DDR3 firmware -> BL31
                 -> KM7 U-Boot 2019.01 -> Linux 5.15.137 + km7.dtb
```

The required S905Y4 FIP header is retained in the owned U-Boot snapshot and is
also checksum-pinned in the source lock.

### Firmware, packages and build tools

| Input | Owned location | Pinning |
|---|---|---|
| Build framework | [`minhdangoz/build`](https://github.com/minhdangoz/build) (this repository) | Normal Git history; `armbian/build` is an upstream merge source, not a board-source dependency |
| TX68 AIC8801 firmware | [`minhdangoz/aic8800-packages`](https://github.com/minhdangoz/aic8800-packages/releases/tag/5.0%2Bgit20260123.5f7be68d-7) | Release `5.0+git20260123.5f7be68d-7` plus SHA256 for both `.deb` files |
| TX68 signing/pack material | Private `minhdangoz/tx68-secure-pack` release | Dated encrypted archive plus SHA256 |
| Host packages/toolchains | Ubuntu/Armbian build infrastructure | External build infrastructure; not a board source of truth |

For ownership policy, restore instructions, updating and rollback, see
[`docs/SOURCE_OWNERSHIP.md`](docs/SOURCE_OWNERSHIP.md). Hardware and build
details live in [`docs/TX68_README.md`](docs/TX68_README.md) and
[`km7/README.md`](km7/README.md).

## Purpose of This Repository

The **Armbian Linux Build Framework** creates customizable OS images based on **Debian** or **Ubuntu** for **single-board computers (SBCs)** and embedded devices.

It builds a complete Linux system including kernel, bootloader, and root filesystem, giving you control over versions, configuration, firmware, device trees, and system optimizations.

The framework supports **native**, **cross**, and **containerized** builds for multiple architectures (`x86_64`, `aarch64`, `armhf`, `riscv64`) and is suitable for development, testing, production, or automation.

> **Looking for prebuilt images?** Use [Armbian Imager](https://github.com/armbian/imager/releases) — the easiest way to download and flash Armbian to your SD card or USB drive. Available for Linux, macOS, and Windows.

## Quick Start

```bash
git clone https://github.com/minhdangoz/build
cd build

# TX68: current/mainline-derived Linux 6.18
./compile.sh BOARD=tx68 BRANCH=current RELEASE=noble BUILD_DESKTOP=yes DESKTOP_ENVIRONMENT=gnome KERNEL_CONFIGURE=no

# KM7: legacy/vendor Linux 5.15
./compile.sh BOARD=km7 BRANCH=legacy RELEASE=noble BUILD_DESKTOP=yes DESKTOP_ENVIRONMENT=gnome KERNEL_CONFIGURE=no
```

<a href="#how-to-build-an-image-or-a-kernel"><img src=".github/README.gif" alt="Build demonstration" width="100%"></a>

## Build Host Requirements

### Hardware
- **RAM:** ≥8GB (less with `KERNEL_BTF=no`)
- **Disk:** ~50GB free space
- **Architecture:** x86_64, aarch64, or riscv64

### Operating System
- **Native builds:** Armbian or Ubuntu 24.04 (Noble)
- **Containerized:** Any Docker-capable Linux
- **Windows:** WSL2 with Armbian/Ubuntu 24.04

### Software
- Superuser privileges (`sudo` or root)
- Up-to-date system (outdated Docker or other tools can cause failures)

## Resources

- **[Documentation](https://docs.armbian.com/Developer-Guide_Overview/)** — Comprehensive guides for building, configuring, and customizing
- **[Website](https://www.armbian.com)** — News, features, and board information
- **[Blog](https://blog.armbian.com)** — Development updates and technical articles
- **[Forums](https://forum.armbian.com)** — Community support and discussions

## Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on reporting issues, submitting changes, and contributing code.

## Support

### Community Forums
Get help from users and contributors on troubleshooting, configuration, and development.
👉 [forum.armbian.com](https://forum.armbian.com)

### Real-time Chat
Join discussions with developers and community members on IRC or Discord.
👉 [Community Chat](https://docs.armbian.com/Community_IRC/)

### Paid Consultation
For commercial projects, guaranteed response times, or advanced needs, paid support is available from Armbian maintainers.
👉 [Contact us](https://www.armbian.com/contact)

## Contributors

Thank you to everyone who has contributed to Armbian!

<a href="https://github.com/armbian/build/graphs/contributors">
  <img alt="Contributors" src="https://contrib.rocks/image?repo=armbian/build" />
</a>

## Armbian Partners

Our [partnership program](https://forum.armbian.com/subscriptions) supports Armbian's development and community. Learn more about [our Partners](https://armbian.com/partners).
