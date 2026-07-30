# Why this project exists, and what came before it

This is a history/decision doc, not a build guide. It records what the two
prior board-bringup projects actually achieved, where each one got stuck, and
the specific technical reason we started a third project on `armbian/build`
instead of continuing either of them.

## The three sibling checkouts

| Path | What it is |
|---|---|
| `/media/jimmy/WORK/AOSP/orangepi-build` | TX68 (Allwinner H618) Ubuntu image, built on Xunlong's Orange Pi vendor build framework (itself an Armbian-derived fork), against the Android vendor BSP kernel/U-Boot for DRAM/boot0 correctness. |
| `/media/jimmy/WORK/AOSP/fenix` | KM7 (Amlogic S905Y4) Ubuntu image, built on Khadas's own `fenix` build framework (also Armbian-derived), against the Khadas vendor 5.15 kernel. |
| `/media/jimmy/WORK/AOSP/build` (this repo) | Upstream `armbian/build`, cloned fresh, aiming to cover **both** device families (H618 + S905Y4) from one build system instead of two separate vendor forks. |
| `/media/jimmy/WORK/AOSP/pp618`, `/media/jimmy/WORK/AOSP/s905y4` | The two devices' Android AOSP source trees — reference-only, used to cross-check DRAM/DT values and identify the fitted WiFi/BT/GPU parts. Not edited by any of the above. |

## Project 1 outcome: orangepi-build / TX68 (H618)

Verified on real hardware (see `orangepi-build/docs/TX68_STABILITY_AND_RISKS.md`):
secure eMMC boot, Ubuntu Jammy XFCE, Ethernet, 1920x1080 HDMI, working
2.4/5 GHz WiFi + Bluetooth 5.2 (AIC8800 vendor driver, board-specific quirks
solved), FD650 front-panel clock, Mali G31 vendor kernel module loaded
(`mali0` probes, UK ABI 11.17), Cedar video decode Oops fixed, Firefox 153
installs and renders via the vendor BSP kernel with a backported BPF-attach
capability-check patch.

Still open: Mesa renders through **llvmpipe** (software) — no DRM/V4L2 device
nodes exist for the vendor Mali blob to hand off to, so there is no GPU- or
video-hardware-accelerated desktop despite the module loading correctly.
FFmpeg hardware encode/decode is unimplemented for the same reason. This is a
kernel/userspace integration gap in the vendor 5.4 BSP tree, not a hardware
fault.

## Project 2 outcome: fenix / KM7 (S905Y4)

Fenix reached a full successful eMMC/SD boot (`km7_build.log`, exit code 0)
after fixing several KM7-specific regressions inherited from the Khadas
VIM1S profile it was copied from — documented in
`fenix/docs/KM7_S905Y4_BRINGUP_AND_RECOVERY.md` and
`fenix/docs/KM7_HARDWARE_SPECS.md`:

- an eMMC/initramfs deadlock (`amlogic-mmc.ko` was in the rootfs but not the
  initramfs, so the boot rootfs could never be found),
- a completely missing `/etc/modules`, so WiFi, Bluetooth, all video-decode
  modules, and the audio codec never loaded,
- two GPIO pinmux conflicts that silently broke WiFi's 32 kHz clock and the
  FD650 front-panel display,
- a U-Boot HDMI HPD-polling bug that forced `vout=none` (blank output)
  whenever hotplug detection raced the display,
- the VIM-COMMON rootfs overlay (fan control, CPU governor, udev rules,
  HDMI hotplug scripts) never being applied because the board-name regex
  didn't match `KM7`.

Hardware video decode (VPU/VDEC) was brought fully working: microcode,
kernel modules, and the `gstreamer_aml` userspace plugins are all now
correctly installed and load.

**Two things were left explicitly unsolved, and both are why this new
project exists:**

1. **GPU hardware acceleration never worked.** The vendor 5.15 KM7/VIM1S
   `&gpu` DT node compiles to `compatible = "arm,malit60x", "arm,malit6xx",
   "arm,mali-midgard"`. The kernel's own Panfrost driver only binds
   `"arm,mali-bifrost"`. So `mali_kbase` (`CONFIG_MALI_MIDGARD=m`) claims the
   device and creates `/dev/mali0`, but with no matching userspace GL driver
   installed for that binding, the desktop falls back to `llvmpipe`. The
   KM7 doc says outright: "moving the GPU node to the Panfrost binding — the
   latter is untested on this vendor tree."
2. **WiFi/BT never worked**, and not because of a pinmux bug this time — the
   fitted part is an **Amlogic W1** (`vendor=0x8888 device=0x8888` on all 7
   SDIO functions), not the Broadcom part Fenix's `bcmdhd` driver expects.
   Porting the vendor `w1` driver forward to a 5.15 kernel is real, bounded
   work (~15 files: removed `set_fs`/`get_fs`, changed cfg80211 op
   signatures, a stale bundled minstrel copy) but was not completed.

So both prior projects independently hit the **same wall**: a vendor kernel
tree whose Mali driver binding doesn't line up with the mainline Panfrost
driver, leaving the GPU on software rendering, plus incomplete WiFi/BT driver
ports for whatever non-reference radio each specific board actually shipped.

## Why armbian/build, now

Checking `armbian/build` directly (not assumed) turned up an important
asymmetry between the two SoC families — this is the actual reason to
prioritize the H618 side first:

- **H618 (`orangepizero3.csc`) is genuinely mainline.** `KERNEL_TARGET=
  "current,edge"`, mainline U-Boot (`sunxi64` family, v2026.07), and the POC
  build pulled a prebuilt **kernel 6.18** artifact from Armbian's cache
  (`ghcr.io/armbian/os/kernel-sunxi64-current`). Mali-G31 on H618 is a
  Bifrost part, so the in-tree mainline Panfrost driver binds it directly —
  no vendor binding mismatch to work around. This is the part of the
  TX68/orangepi-build GPU wall that mainline plausibly just solves.
- **S905Y4 (`khadas-vim1s.conf`) is *not* mainline in armbian/build either.**
  `KERNEL_TARGET="legacy"`, and the kernel source is
  `khadas/linux.git` branch `khadas-vims-5.15.y` with `khadas/common_drivers`
  — **the same vendor 5.15 kernel Fenix already builds.** There is no free
  kernel upgrade for the Y4 side from switching build systems. What *is*
  different: `khadas-vim1s.conf` sets `DEFAULT_OVERLAYS="panfrost"`, meaning
  Armbian's own DT/overlay may already carry the Bifrost-compatible GPU
  binding that Fenix's KM7 doc flagged as untested — that needs to be
  checked directly against Armbian's own DTS once the H618 POC is done, not
  assumed from the config file alone.
- **VIM1S's WiFi is not KM7's WiFi.** `khadas-vim1s.conf` provisions a
  Broadcom `BCM4345C5` firmware symlink (`AP6256` module). KM7 has the
  **Amlogic W1** part instead. Whatever Armbian does for VIM1S WiFi will not
  apply to KM7 as-is — the W1 driver porting work documented in Fenix's
  bring-up doc is still required regardless of which build framework hosts
  it.

## The plan this justifies

1. Prove the mainline path on H618 first (`orangepizero3`, GNOME desktop,
   kernel 6.18) — in progress, tracked in this session. This validates
   whether mainline + Panfrost actually delivers HW-accelerated GNOME on the
   same SoC family as TX68, before spending any effort porting TX68's own
   DRAM/DT to it.
2. Only after that POC boots with confirmed GPU acceleration, do the same
   check for the S905Y4/VIM1S side specifically for the Panfrost GPU binding
   (not the kernel version, which doesn't change).
3. Treat WiFi/BT on both TX68 and KM7 as separate, board-specific driver
   ports regardless of which build framework is used — Armbian does not
   make this part easier for either non-reference radio.
4. Decide whether to actually port TX68's and KM7's vendor DRAM/DT data into
   this repo (`config/boards/`) only once step 1 (and ideally step 2) prove
   the mainline GPU story is real, since that is the one concrete advantage
   over the existing, already-largely-working `orangepi-build` and `fenix`
   trees.
