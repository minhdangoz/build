# KM7 Hardware / Driver Specification

Board: Mecool KM7. SoC: Amlogic S905Y4 (silicon family S4, board variant
`s4_s905y4_ap222` / `AP222`). Same SoC family as Khadas VIM1S, different
board wiring.

The hardware source of truth for this port is the Android KM7 tree at
`/media/jimmy/WORK/AOSP/s905y4`: the board product under
`device/amlogic/KM7`, the 4 GB board DTS
`common/arch/arm64/boot/dts/amlogic/s4_s905y4_ap222_drm_4g.dts`, its S4 SoC
includes, and the AP222 U-Boot configuration. Fenix/VIM1S is a build-system
reference only and must not override KM7 board data. Live identification from
the physical unit takes precedence where the Android tree describes multiple
SKUs or conflicts with public product material.

The resulting values are carried by [`config/boards/km7.csc`](../config/boards/km7.csc),
the tracked KM7 U-Boot patch series and the tracked kernel/common-drivers patch
series in this repository. Where the source carries a live-verified comment
(hardware tested on a real unit), it is called out explicitly. See
[KM7_S905Y4_BRINGUP_AND_RECOVERY.md](KM7_S905Y4_BRINGUP_AND_RECOVERY.md) for
the original bring-up evidence and [`../km7/README.md`](../km7/README.md) for
the current Armbian build/acceptance workflow.

## CPU

- **4x ARM Cortex-A35**, confirmed on the physical KM7 by MIDR
  `0x00000000411fd040` (Arm implementer `0x41`, part `0xd04`). Android's
  `meson-s4.dtsi` incorrectly declares Cortex-A55; that DT compatible is stale
  metadata and must not override the silicon ID. PSCI enable-method, 64-bit
  (armv8).
- All four silicon-bin OPP tables reach 2004 MHz. Depending on the secure
  firmware-selected table, that OPP requests 939–1009 mV; the S4 PWM regulator
  supports up to 1049 mV and the S4 system PLL contains the matching 2004 MHz
  rate.
- This project clamps scaling to 500–2004 MHz and defaults to the
  `performance` governor. Khadas also specifies the S905Y4 as a 2.0 GHz SoC.
  Fenix's old 2208 MHz maximum is not a vendor OPP and is deliberately not
  copied.
- Multi-table OPP (`multi_tables_available`) bound to all 4 CPU nodes.

## GPU

- **ARM Mali-G31**, confirmed live by Panfrost as GPU ID `0x7093`; the runtime
  reports one shader core (`shader_present=0x1`) and one L2 slice
  (`l2_present=0x1`). Android's Bifrost node declares `num_of_pp = <2>` and
  `sc_mpp = <1>`, while the KM7 kernel build selects Mali driver `r43p0`. The
  previous "Mali G52 MP8 / gondul 25p0" claim was wrong.
- Display server: Wayland for desktop builds, GBM for server builds
  (`GPU_PLATFORM` in KM7.conf).
- The default Armbian `s4-s905y4-panfrost.dtbo` overlay replaces the GPU
  compatible with `arm,mali-bifrost`. Panfrost 1.2.0 now probes successfully
  on real KM7 hardware; the userspace renderer still needs `glxinfo -B` proof.
- GPU DVFS table: 285.714/400/500/666.666/846 MHz. The last two table entries
  both reference the 846 MHz configuration, exactly as in the Android 4 GB DTS.
- Panfrost logs an initial clock of approximately 500 MHz. This is the DTS
  assigned boot clock, not evidence of a 500 MHz cap: the driver subsequently
  installs the OPP table and uses the `simple_ondemand` devfreq governor. The
  missing optional `mali` regulator warning is expected with this S4 DT, whose
  GPU OPPs all request the same 1.15 V and which declares no `mali-supply`.

## GPU vs VPU — they are separate blocks, do not conflate them

This trips people up constantly on Amlogic, so state it plainly:

- **GPU** = Mali-G31 Bifrost-family block, live-identified as ID `0x7093`.
  It provides 3D/GLES for the desktop and is irrelevant to video decoding.
- **VPU/VDEC** = the Amlogic hardware video decoders driven by the `amvdec_*`
  drivers. This is what must handle H.264/H.265/VP9/AV1 so playback does not
  land on the CPU. It needs **no** Mali userspace at all.

### VPU (hardware video decode) — what it takes to actually work

Three things, all of which were broken on KM7 and are now fixed:

1. **Microcode.** `/lib/firmware/video/video_ucode.bin`, installed by
   `build-board-deb` from
   `archives/hwpacks/video-firmware/Amlogic/$KHADAS_BOARD/`. There was no
   `KM7` directory, so the `cp` failed and images shipped with no VDEC
   microcode — the decoders cannot decode a single frame without it. The S4
   blob (`md5 ad08bd…`, distinct from the g12a and t7 ones) is now present
   under `KM7/`, and a missing directory is now a hard build error instead of
   a line in the log.
2. **Modules.** `media_clock`, `firmware`, `decoder_common`, `stream_input`,
   `amvdec_*`, `amvdec_ports`, `media_sync`. None have a DT modalias, so they
   only load from `/etc/modules` — which KM7 did not have at all.
3. **Userspace.** `gstreamer_aml` carries Amlogic's hardware-decode GStreamer
   plugins. Its prebuilt tree is laid out per board with no `KM7` entry, so
   the package's fallback `cp noble/arm64/KM7/5.15/*` hit a missing
   directory. `PREBUILT_BOARD="VIM1S"` in `config/boards/KM7.conf` now
   redirects that lookup (same silicon), as it does for
   `optee_video_firmware_deb_aml` (secure-video TAs).

Verify on the running board:

```bash
ls -l /lib/firmware/video/video_ucode.bin
lsmod | grep -E 'amvdec|decoder_common|stream_input|media_clock'
ls /dev/amstream_* /dev/video*
cat /sys/class/vdec/vdec_status          # shows the active decoder + fps
gst-inspect-1.0 | grep -i aml            # amlvdec / amlvsink plugins
```

`/sys/class/vdec/vdec_status` naming a decoder while a clip plays is the
proof that decode is on the VPU. A CPU-bound `ffmpeg`/`mpv` process at ~100%
with an empty `vdec_status` means it fell back to software.

### GPU — kernel driver confirmed; userspace renderer proof still required

Fenix proved that the unmodified vendor node compiled as Midgard-compatible,
letting `mali_kbase` claim the device while XFCE rendered through llvmpipe.
This project enables Armbian's Panfrost overlay by default; decompiling the
tracked overlay shows that it replaces the compatible with
`"amlogic,meson-g12a-mali", "arm,mali-bifrost"`. Runtime KM7 logs confirm
Panfrost probes the Mali-G31 ID `0x7093` and registers DRM successfully. That
proves kernel binding, but not that Mesa/GNOME is rendering on the GPU rather
than llvmpipe. Confirm userspace and runtime DVFS with:

```bash
glxinfo -B | grep -E 'OpenGL renderer|OpenGL version'
dmesg | grep -Ei 'panfrost|mali|gpu'
for d in /sys/class/devfreq/*; do
    grep -q bifrost "$d/name" 2>/dev/null || continue
    echo "$d"
    cat "$d"/{name,governor,cur_freq,available_frequencies}
done
```

## RAM

- **4 GB is physically fitted**, confirmed live via U-Boot `bdinfo`.
- **Linux 5.15 receives 3.5 GB** through
  `linux,usable-memory = <0x0 0x0 0x0 0xe0000000>`, matching Amlogic's
  dedicated `s4_s905y4_ap222_drm_4g.dts` profile. The final 512 MB below
  4 GB contains the S4 MMIO aperture, including CBUS at `0xfe000000`, and is
  intentionally not exposed as System RAM.
- Do not declare a contiguous 4 GB range (`0x1 0x0`): it overlaps MMIO,
  causes device `ioremap()` failures and crashes the vendor media probe chain.
  The previous 2 GB value was safe but incorrectly used the vendor 2 GB
  profile's limit on this 4 GB unit.
- Do not confuse the physical capacity, U-Boot's DRAM detection and Linux's
  current usable-memory window; they are three different observations.
- DDR firmware type: `ddr3` (`CONFIG_DDRFW_TYPE="ddr3"` in km7_defconfig).

## Storage

| Interface | DT node    | Bus width | Notes |
|-----------|-----------|-----------|-------|
| eMMC      | `sd_emmc_c` | 8-bit | `cap-mmc-highspeed`, `mmc-ddr-1_8v`, `mmc-hs200-1_8v` declared, but `max-frequency` capped at **100 MHz** (not 200 MHz) to match the vendor-proven Android DTB value — km7.dts comment notes this may relate to `emmc: resp timeout, cmd8/cmd55` messages seen on every boot. `tx_delay = 0xa` and `ignore_desc_busy` are also carried over from the vendor DTB for the same reason. HS400 is present but commented out. |
| SD card   | `sd_emmc_b` | 4-bit | Card-detect on `GPIOC_6`, data1/wake on `GPIOC_1`. `max-frequency = 200000000` but UHS modes (SDR50/SDR104) are commented out — effectively high-speed only. |
| NAND      | `mtd_nand`  | — | `status = "disabled"` — board has no NAND, eMMC-only. |
| SDIO      | `sd_emmc_a` | 4-bit | Non-removable, on-board WiFi, not general storage. The `brcm,bcm4329-fmac` compatible is Amlogic's generic SDIO-WiFi string — the actual part is an Amlogic W1 (SDIO id `0x8888:0x8888`). See Networking. |

eMMC boot requires `amlogic-mmc.ko` (module) present in the initramfs — see
the bring-up doc for the module-list fix; without it Linux cannot see any
`/dev/mmcblk*` device at all.

## Networking

- **Ethernet**: SoC-internal EPHY (`internal_ephy`, `ethernet-phy-id0180.3301`)
  over RMII, `max-speed = 100` → **10/100 Mbps only, no Gigabit**.
- **WiFi**: **Amlogic W1, not Broadcom.** The DT node uses the generic
  `brcm,bcm4329-fmac` compatible on `sd_emmc_a` — that string is what
  Amlogic puts on *any* SDIO WiFi slot and is not evidence of a Broadcom
  part. Live-verified: the SDIO bus enumerates 7 functions, every one
  reporting `vendor=0x8888 device=0x8888`, which is
  `VENDOR_AMLOGIC`/`PRODUCT_AMLOGIC` from
  `vendor/wifi_driver/amlogic/w1/wifi/project_w1/common/fi_sdio.h` in the
  Android tree. The vendor Android build config
  (`device/amlogic/KM7/wifibt.build.config.trunk.mk`) lists `w1` among its
  WiFi modules, consistent with this.

  Consequence: **`dhd` (bcmdhd) can never drive it.** Fenix builds only
  `bcmdhd` plus the upstream drivers; there is no `aml_w1` anywhere in the
  kernel tree. On hardware `dhd` powers the adapter, fails to find a
  Broadcom part and gives up with `_dhd_module_init: Exit err=-19`.
  This repository now tracks the ported W1 driver as kernel patch `0007` and
  installs its RF tables. Association on the first Armbian image is not yet
  claimed until verified on the physical board.

  Power-on `GPIOX_6`, interrupt `GPIOX_7`, and the 32.768 kHz reference
  clock on `GPIOX_16` via `&pwm_ef` channel 0 (`wifi_pwm_conf`). That
  clock is mandatory: without it the part never leaves reset and the SDIO
  bus reports `sdio vendor is 0x0`.
- **Bluetooth**: `aml_bt` node — reset & BT-enable share `GPIOX_17`,
  wake-up on `GPIOX_18`, host-wake on `GPIOX_19`. The W1 is a WiFi+BT
  combo. The family Broadcom `hciattach` path is intentionally disabled for
  KM7. HCI behavior remains unverified in the new Armbian image and must not
  be inferred from WiFi association alone.
- PCIe controller (`&pcie`) is present in silicon but disabled on this board
  (`status = "disable"`, reset gpio `GPIOX_7` — note this collides with the
  WiFi interrupt GPIO above, consistent with PCIe being unused here).

## USB

- `dwc2_a` (USB2 OTG controller): forced **host-only** (`controller-type = <1>`).
  A km7.dts comment documents that the inherited base value (`3`, out of the
  documented 0/1/2 range) left the USB host stack never enumerating any
  device — live-verified via dmesg (`root=/dev/sda2 rootwait` hung forever).
- `usb2_phy_v2`: 2 ports (`portnum = <2>`).
- `usb3_phy_v2`: `portnum = <0>` (no USB3 port wired), forced host mode
  (`otg = <0>`) rather than ID-pin detection — km7.dts comment notes ID-pin
  based OTG (`otg = 1`, inherited from kvim1s.dts) may never resolve on
  KM7's actual wiring.

## Display / HDMI

- `amhdmitx` / `drm_amhdmitx`: enabled. HDCP is explicitly **disabled**
  (`hdcp = "disabled"`) to match Android's KM7 4 GB DTS; the previous enabled
  setting came from the wrong board reference.
- CVBS output (`drm_amcvbsout`) also enabled; LCD output (`drm_lcd`) disabled
  — HDMI/CVBS board, no panel.
- Framebuffer (`&fb`) disabled in favor of DRM/VPU path (`drm_vpu`,
  `status = "okay"`), default resolution `1920x1080`.
- VPU clock level is `7`, matching Android KM7; the previous level `8` was not
  the board source of truth.
- `vdin0`/`vdin1` video-input paths present for capture, `vdin1` wired to a
  reserved CMA pool.

## Audio

- `auge_sound` ALSA card ("AML-AUGESOUND") with 7 DAI links: 2x TDM analog
  out, I2S-to-HDMI, I2S to external codec (`amlogic_codec`), PDM built-in
  mic, SPDIF out, SPDIF-to-HDMI (`spdifb`), and a loopback link.
- Speaker mute GPIO `GPIOH_8` (active-low), av-out mute `GPIOH_5`.
- PDM mic and both SPDIF outputs are enabled; asrcb/loopbackb resample
  paths are disabled by default.

## Front-panel display (FD650)

The board carries a 4-digit 7-segment module on the front-panel header —
visible on the photo in
[KM7_S905Y4_BRINGUP_AND_RECOVERY.md](KM7_S905Y4_BRINGUP_AND_RECOVERY.md).

- Part: **FD650**, 2-wire (CLK/DAT), no strobe.
- Pins: `scl-gpios = GPIOD_7`, `sda-gpios = GPIOD_6`. Taken from the vendor
  Android `KM7.dtb`, which describes all three front-panel variants on the
  same two pins — `fd655_dev` and `fd650_dev` (2-wire) and `fd628_dev`
  (3-wire, same two pins plus strobe on `GPIOD_8`) — and enables the 3-wire
  `fd628_dev`. This unit has the 2-wire part, so km7.dts enables `fd650`.
- Driver: `drivers/led/fd650.c` in common_drivers, built into
  `amlogic-led.ko` via `CONFIG_AMLOGIC_LEDS_FD650=y` (added to
  `kvims_defconfig`). `amlogic-led` is a module and is in the KM7
  `/etc/modules` list.
- **The 5.15 binding is not the vendor 5.4 binding.** common_drivers ships a
  rewritten driver matching `"amlogic,fd650"` with `sda-gpios`/`scl-gpios`;
  the vendor node (`"amlogic,fd650_dev"` with
  `fd650_gpio_dat`/`fd650_gpio_clk`) will never probe against it.
- `mboxes` / `use-bl30-ctrl` are deliberately omitted — those hand the panel
  to the BL30 co-processor. Direct GPIO bit-banging is used instead, which is
  also the only mode where the `fd650_sec` attribute works.
- `fd650-gpio,delay-us` is not worth setting: `fd650_probe()` has an inverted
  check (`if (!ret) bus->udelay = DEFAULT_UDELAY;`) that discards the DT
  value whenever the property reads successfully.

Runtime interface (`<node-name>` is `fd650`):

```bash
ls /sys/class/leds/fd650/                       # fd650_display, fd650_clear, fd650_sec, fd650_time
echo "1 1234" > /sys/class/leds/fd650/fd650_display   # "<colon_on 1|0> <up-to-4-chars>"
echo "0 boot" > /sys/class/leds/fd650/fd650_display
echo 1       > /sys/class/leds/fd650/fd650_clear      # shows "****"
```

**`GPIOD_8` collision worth knowing:** on FD628 boards `GPIOD_8` is the
front-panel strobe, and U-Boot's `upgrade_key` in `km7.h` polls exactly that
pin (`if gpio input GPIOD_8`). That is more evidence the GPIOD_8 upgrade key
is bogus for this hardware — see the recovery-key section of the bring-up
doc. FD650 being 2-wire means `GPIOD_8` is at least not contended here.

## IR / Remote

- `&ir` enabled with custom key map (`custom_maps_linux`) via
  `remote_pins`.

## Buttons / Keys

- ADC keypad (`adc_keypad`, SARADC channel 0): `standby`, `vol+`, `vol-`
  keys, threshold values `20/910/630` (raw ADC, `val = voltage/1800mV*1023`).
- GPIO keypad (`gpio_keypad`, polling mode): `bluetooth` key on `GPIOD_2`,
  `mute` key on `GPIOD_3`.
- U-Boot carries the inherited GPIOD_8 check plus the required SARADC
  `adc_update_key` (channel 0, range 0..50), matching the stock AP222 physical
  recovery path. Both run from `CONFIG_PREBOOT`. See the bring-up doc
  for the regression this fixes.

## I2C peripherals

- `i2c1` (300 kHz): two LED drivers — `tlc59116` @ 0x60 (4x RGB LED) and
  `aw9523b` @ 0x5b (5x RGB LED, reset gpio `GPIOD_10`).
- `i2c3` (300 kHz), `i2c4` (300 kHz): wired for the DVB tuner/demod stack
  (`r836_tuner`, `av2018_tuner`, `cxd2856` demod) — TV-tuner variant
  hardware, not populated/used on a plain Ubuntu desktop image.
- `i2c0`, `i2c2` aliased but not configured with peripherals in km7.dts.

## TV tuner / DVB — wired in DT, **not populated**, disabled

- `dvb-extern`, `dvb-demux` and `aml_dtv_demod` are all `status = "disabled"`
  in km7.dts, matching the vendor Android `KM7.dtb`. Verified by decompiling
  `device/amlogic/KM7-kernel/5.4/KM7.dtb` (Amlogic multi-DTB, `s4_s905y4/4g`
  entry) — all three are disabled there too — and `dtbo.img` from the same
  directory, whose only two fragments add `dummy-battery` and
  `dummy-charger`, so nothing re-enables them at runtime.
- The wiring is kept in the DTS for a tuner-populated variant: up to 3
  frontends (2x internal DVB-C + 1x external DVB-S `cxd2856` over `i2c4`)
  and 4 tuner slots (`r836_tuner` x2, `av2018_tuner` x2).
- They were briefly enabled during bring-up. That cost i2c3/i2c4 probes of
  absent tuners, the `PDID_S4_DEMOD` power domain, the `dvb_s_ts0` pinmux
  claim, and a `dvb-demux` `reg` window of `0xfe000000+0x480000` blanketing
  the peripheral aperture the HDMI TX register bases sit in.

## Known deltas from the vendor Android DTB

Produced by decompiling the vendor `KM7.dtb` and diffing node `status`
against the built `km7.dtb`. Everything not listed matches.

| Node | Vendor | km7.dts | Note |
|------|--------|---------|------|
| `adc_keypad` | disabled | **okay** | Vendor does not use the SARADC keypad. Enabled here with KM7 thresholds; unverified against the real button wiring. |
| `gpio_keypad` | disabled | **okay** | Same — `bluetooth`/`mute` on `GPIOD_2`/`GPIOD_3` is unverified. |
| `provisionkey` | disabled | **okay** | Harmless, but a vendor-intentional difference. |
| `ledlight` (`power_led`) | okay | replaced by `gpio-leds` | GPIOD_10 is asserted at boot and exposed as `panel_power`, matching the vendor's active-high behavior. |
| `fd628_dev` | okay | replaced by `fd650` | The observed unit carries a two-wire FD650, using the 5.15 binding on GPIOD_6/GPIOD_7. |
| `mhu` | okay | absent | Expected: 5.15 uses `mbox_fifo`/`mbox_devfs` instead. |

Audio (`auge_sound`), Ethernet, thermal (`p_tsensor`, `thermal-zones`),
WiFi/BT (`aml_wifi`, `aml_bt`, `wifi_pwm_conf`) and the whole HDMI/DRM
display chain were diffed property-by-property against the vendor blob and
differ only in phandle numbering.

## Boot / Storage-controller firmware notes (U-Boot)

- `CONFIG_BL30_SELECT="s4_ap222"` — BL30 (Amlogic RTOS co-processor
  firmware) selects the AP222 board variant.
- `CONFIG_DEBUG_UART_BASE=0xfe07a000`, 24 MHz clock — matches
  `earlycon=meson,0xfe07a000` in the kernel bootargs.
- `CONFIG_DEFAULT_DEVICE_TREE="meson-s4-ap222"`.
- U-Boot prompt: `km7#` (`CONFIG_SYS_PROMPT`).
- `CONFIG_CMD_SARADC=y`, `CONFIG_CMD_GPIO=y`, `CONFIG_CMD_MMC=y`,
  `CONFIG_CMD_USB=y`, `CONFIG_DM_GPIO=y` all present, so both the GPIO and
  SARADC recovery-key paths above are usable at runtime.
- Serial console aliases: `serial0=uart_B` (main console, `ttyS0`),
  `serial1=uart_A` (has RTS/CTS enabled), `serial2..4 = uart_C/D/E`.

## Partition layout (eMMC install)

Uses `partition_debian_linux.dtsi`, not the Android partition table —
required so the EMMC install's `rootfs` partition exists at all (Amlogic
USB Burning Tool fails instantly against the Android table with "Can't find
your download part(rootfs)"). See km7.dts top-of-file comment.
