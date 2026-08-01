# Build TX68 (Allwinner H618)

Hướng dẫn build ảnh Linux mainline cho TV box TX68 / m1k_go.

File này chỉ nói **cách làm**. Hai file kia trả lời hai câu hỏi khác:

| Cần biết | Đọc |
|---|---|
| Phần cứng là gì — chân, điện áp, xung, chip nào | [`docs/TX68_HARDWARE.md`](../docs/TX68_HARDWARE.md) |
| Vì sao phải dùng U-Boot vendor, secure boot chạy ra sao | [`docs/SECURE_BOOT.md`](../docs/SECURE_BOOT.md) |

> **Trước khi sửa DTS, đọc `TX68_HARDWARE.md`.** Gần như mọi lỗi tốn nhiều thời
> gian nhất của dự án đều là một con số bị đoán thay vì tra. Con số nào chưa có
> trong file đó thì đi tìm nguồn vendor rồi ghi vào, đừng đoán.

---

## 1. Tổng quan

TX68 khoá secure boot, nên chuỗi khởi động **bắt buộc** là của vendor:

```
BootROM → Boot0 → BL31 → U-Boot (vendor 2018.05, 32-bit) → Linux 6.18 mainline
                   ↑ bàn giao ở AArch32 (spsr 0x1d3)
```

Hệ quả quan trọng: **không dùng được mainline U-Boot**. BL31 chạy U-Boot ở chế độ
32-bit, mà mainline U-Boot cho H616 là 64-bit → chết ngay. Toàn bộ defconfig
`sun50iw9` của vendor cũng đều 32-bit. Vì vậy ta **vá U-Boot vendor** thay vì thay nó.

armbian-build chỉ tạo ra kernel + DTB + rootfs. Ba thứ đó được nhét vào chuỗi boot
vendor bằng script đóng gói riêng.

---

## 2. Chuẩn bị

### Thư mục bí mật (không có trong git)

Hai thư mục này bị `.gitignore` vì chứa **khoá ký secure boot** của vendor:

| Thư mục | Nội dung | Lấy từ đâu |
|---|---|---|
| `tx68/android-pack/` | `pack_out/`, `pctools-linux/`, `keys/`, `sign_config/` | `/home/jimmy/AOSP/pp618` (cây Android BSP) |
| `tx68/uboot-debs/` | `linux-u-boot-next-tx68_0.1.0_arm64.deb` | orangepi-build |

Hai thư mục private ở trên được backup bằng `age` trong private release
`minhdangoz/tx68-secure-pack`; chúng không được commit plaintext. Trên clean
checkout, restore bằng `./tx68/scripts/tx68-restore-secure-pack.sh`. Source và
revision bất biến của kernel, vendor U-Boot và AIC8801 nằm tại
`config/boards/tx68-km7-source-lock.inc`; xem `docs/SOURCE_OWNERSHIP.md`.

Không có chúng thì không ký được TOC1 → máy không boot. Đây là thứ duy nhất
không thể tái tạo từ repo này.

### Nguồn U-Boot vendor

Mặc định script clone snapshot U-Boot vendor **2018.05** bất biến từ
[`minhdangoz/tx68-u-boot`](https://github.com/minhdangoz/tx68-u-boot), commit
[`d7e300ad8182`](https://github.com/minhdangoz/tx68-u-boot/commit/d7e300ad8182b8fbd15f66bcb45c4e62ac23a3a2),
vào `cache/sources/tx68-u-boot`. Có thể dùng cây local để phát triển bằng biến
`TX68_UBOOT_SRC`, nhưng production build mặc định luôn quay lại commit đã pin.

Kernel là Linux **6.18.41**, nhánh Armbian `current`, lấy từ snapshot
[`minhdangoz/linux-stable@457936105aed`](https://github.com/minhdangoz/linux-stable/commit/457936105aed97a31778991bff97e8a0346d1bff).
AIC8801 firmware/DKMS lấy từ release cố định
[`minhdangoz/aic8800-packages`](https://github.com/minhdangoz/aic8800-packages/releases/tag/5.0%2Bgit20260123.5f7be68d-7)
và kiểm tra SHA256 trước khi dùng. Full hash và upstream provenance nằm tại
[`config/boards/tx68-km7-source-lock.inc`](../config/boards/tx68-km7-source-lock.inc).

### Công cụ host

```bash
sudo apt install gcc-arm-linux-gnueabi device-tree-compiler \
                 e2fsprogs u-boot-tools rsync busybox dos2unix xxd jq
```

---

## 3. Quy trình build

### Một lệnh — build raw image và PhoenixSuit eMMC image

```bash
cd /media/jimmy/WORK/AOSP/build
./tx68/build-emmc.sh
```

Wrapper này chạy toàn bộ Bước 1 và Bước 3 bên dưới, dùng sẵn U-Boot
`linux-u-boot-next-tx68-fdtfix_0.1.0_arm64.deb`, rồi kiểm tra SHA256 của cả
raw image và PhoenixSuit image. Chỉ cần chạy riêng Bước 2 khi sửa source hoặc
patch U-Boot.

### Bước 1 — Kernel, DTB, rootfs (armbian)

```bash
cd /media/jimmy/WORK/AOSP/build
./compile.sh \
  BOARD=tx68 \
  BRANCH=current \
  RELEASE=noble \
  BUILD_DESKTOP=yes \
  DESKTOP_TIER=mid \
  DESKTOP_ENVIRONMENT=gnome \
  KERNEL_CONFIGURE=no
```

> Đừng chạy bằng `sudo` — armbian tự xin quyền khi cần.

Kết quả: `output/images/Armbian-unofficial_..._gnome_desktop.img`

Lưu ý `DESKTOP_TIER` mặc định là `mid` khi chạy không tương tác, nên rootfs khá to
(~5.7 GB). Đặt `DESKTOP_TIER=minimal` nếu muốn nhỏ hơn.

X11 được ép mặc định (GNOME chạy trên Xorg, không phải Wayland) tự động qua hook
`post_family_tweaks__tx68` trong `config/boards/tx68.conf` — không cần thêm biến gì.

Bước này lâu (hàng giờ). **Chỉ cần chạy lại khi đổi kernel config hoặc rootfs.**
Sửa DTS thì xem mục 4, nhanh hơn nhiều.

### Bước 2 — U-Boot vendor đã vá

```bash
bash tx68/scripts/tx68-build-uboot.sh
```

Script tự làm: copy cây nguồn ra chỗ ghi được → áp patch `0002`, `0003` → đặt
`CONFIG_BOOTDELAY=3` → build → bọc header Allwinner → xuất
`tx68/uboot-debs/linux-u-boot-next-tx68-fdtfix_0.1.0_arm64.deb`.

Script **tự kiểm tra** bản vá có thật sự vào được binary hay không (dò ký hiệu
trong file object và chuỗi trong `u-boot.bin`). Nếu patch không ăn, script dừng
ngay thay vì xuất ra file hỏng — vì một U-Boot chưa vá nhìn từ ngoài **không khác
gì** bản đã vá, và chỉ lộ ra sau khi nạp vào máy.

Chỉ cần chạy lại khi sửa patch U-Boot.

### Bước 3 — Đóng gói ảnh PhoenixSuit

```bash
export TX68_UBOOT_DEB=$PWD/tx68/uboot-debs/linux-u-boot-next-tx68-fdtfix_0.1.0_arm64.deb
export TX68_BOOT_CMD=tx68/bootscripts/boot-tx68-next.cmd

bash tx68/scripts/tx68-build-phoenix-image.sh \
  output/images/Armbian-unofficial_26.08.0-trunk_Tx68_noble_current_6.18.41_gnome_desktop.img
```

Kết quả: `output/phoenix/..._<timestamp>_phoenixsuite.img`

Script này ký TOC1 bằng khoá vendor, bọc kernel thành uImage (`-A arm`), bọc lại
uInitrd, và gói tất cả vào container IMAGEWTY.

Nó cũng chép `userpatches/firstboot.conf` vào `/root/.not_logged_in_yet` để bỏ
wizard first-boot. Nếu không có bước này thì mỗi lần flash lại phải gõ lại toàn
bộ wizard, vì bước chép của armbian chỉ chạy trong full `compile.sh`, không chạy
khi đóng gói lại rootfs có sẵn. Muốn giữ wizard gốc: `TX68_FIRSTBOOT_CONF=none`.

> Ảnh **chưa** qua bước preseed thì đăng nhập bằng `root` / `1234`
> (`ROOTPWD` ở `lib/functions/configuration/main-config.sh`), rồi wizard chạy.

Full auto-login (không cần gõ gì, kể cả trên console/serial trước khi GDM
hiện) cần **cả hai** biến trong `config/boards/tx68.conf`:
`DESKTOP_AUTOLOGIN="yes"` (GDM) và `CONSOLE_AUTOLOGIN="yes"` (getty tty1 +
ttyS0). Thiếu `CONSOLE_AUTOLOGIN` thì vẫn hiện prompt đăng nhập ở console
trước khi vào desktop — đây chính là "prompt lạ" từng thấy trên phần cứng
thật trước khi sửa.

### Bước 4 — Nạp

Dùng PhoenixSuit / PhoenixCard. Bảng "Partitions to Flash" chỉ hiện `rootfs` là
**đúng** — Boot0/TOC1/U-Boot không phải "partition", chúng được ghi thẳng vào
offset cố định và luôn đi kèm.

---

## 4. Sửa DTS mà không build lại kernel

DTS nằm ở `patch/kernel/archive/sunxi-6.18/dt_64/sun50i-h616-tx68.dts`.

Build lại **chỉ mỗi DTB** (vài giây thay vì vài giờ):

```bash
K=cache/sources/linux-kernel-worktree/6.18__sunxi64__arm64
mkdir -p /tmp/tx68dtb && cd /tmp/tx68dtb

cpp -nostdinc \
  -I "$OLDPWD/$K/scripts/dtc/include-prefixes" \
  -I "$OLDPWD/$K/arch/arm64/boot/dts/allwinner" \
  -I "$OLDPWD/$K/include" \
  -undef -D__DTS__ -x assembler-with-cpp \
  "$OLDPWD/patch/kernel/archive/sunxi-6.18/dt_64/sun50i-h616-tx68.dts" \
  -o tx68.pre
dtc -I dts -O dtb -@ -o sun50i-h616-tx68.dtb tx68.pre
```

Rồi nhét vào ảnh khi đóng gói:

```bash
export TX68_DTB_OVERRIDE=/tmp/tx68dtb/sun50i-h616-tx68.dtb
bash tx68/scripts/tx68-build-phoenix-image.sh output/images/....img
```

`compile.sh` chạy đầy đủ sẽ sinh ra đúng DTB đó từ cùng file DTS, nên đây chỉ là
đường tắt, **không phải nguồn sự thật thứ hai**.

---

## 5. Debug

### Luôn xác nhận đúng ảnh trước khi đọc log

Đây là bài học đắt giá nhất của dự án: đã mất nhiều vòng phân tích log của ảnh cũ.

`tx68/bootscripts/boot-tx68-next.cmd` có biến `tx68_bootscript_ver`. **Tăng nó mỗi
lần build có thay đổi đáng kể.** Nó hiện ra ngay trên `Kernel command line`:

```
tx68_bootscript_ver=9-dram1v5
```

Cách chéo để xác nhận DTB: nhìn dòng `bytes read` đầu tiên sau khi boot script chạy
— đó là kích thước DTB, đổi theo mỗi lần sửa DTS.

### Những dòng cần soi trong log UART

| Dòng | Ý nghĩa |
|---|---|
| `Machine model: TX68` | Đúng DTB. Nếu ra `sun50iw9` là đang chạy DT vendor → sai. |
| `OF: reserved mem: 0x48000000..0x48ffffff` | Vùng BL31 đã được giữ. Thiếu dòng này → Linux ghi đè secure monitor → crash lung tung. |
| `Booting using the fdt blob at 0x46000000` | U-Boot dùng DTB của ta, không phải DTB nội bộ. |
| `axp20x-i2c 0-0036: AXP20x variant AXP313a found` | PMIC lên → mới có nguồn cho eMMC. |
| `mmcblk0: ... p1 p2` | eMMC nhận. |

### Vào được dấu nhắc U-Boot

`CONFIG_BOOTDELAY` mặc định của vendor là **1 giây**, gần như không bấm kịp.
Script build đặt thành 3. Đổi bằng `TX68_BOOTDELAY=5`.

Nếu 3 giây vẫn không dừng được: kiểm tra dây RX của USB-UART (thử gõ ở dấu nhắc
login — không gõ được nghĩa là RX chưa nối).

---

## 6. Các lỗi đã gặp và cách sửa

Ghi lại để không phải chẩn đoán lại từ đầu. Tất cả đều là "Allwinner cắt bớt một
hành vi chuẩn của U-Boot, thứ mà kernel vendor không cần nhưng mainline thì cần".

| Triệu chứng | Nguyên nhân | Sửa ở |
|---|---|---|
| `Machine model: sun50iw9`, eMMC không bao giờ hiện | `bootm` bỏ qua tham số FDT thứ ba, luôn đưa DT vendor cho kernel | patch `0002` |
| `could not set bootargs FDT_ERR_NOSPACE` | DTB nạp từ đĩa không có chỗ trống để thêm `/chosen` | patch `0003` |
| `fdt_initrd: FDT_ERR_BADLAYOUT` | `of_size` không đồng bộ sau khi nới DTB → `totalsize` bị ép nhỏ hơn nội dung | patch `0003` |
| `Failed to allocate page table page` | DTB không có node `/memory`; U-Boot không gọi `arch_fixup_fdt()` trên đường Linux | patch `0003` |
| Máy 4 GB chỉ thấy 2 GB | `dram_init()` kẹp cứng 2048 MiB | patch `0003` |
| Oops `__d_alloc` lúc i2c probe | DT thiếu reservation BL31 → Linux cấp phát đè lên secure monitor | DTS: `bl31@48000000` |
| `vdd-dram: Bringing 1500000uV into 1360000-1360000uV` | DTS ép `dcdc3` xuống 1.36 V trong khi Boot0 huấn luyện DDR3 ở 1.5 V (KHÔNG phải nguyên nhân RCU stall — xem đính chính trong TX68_HARDWARE.md mục 4.1) | DTS: `reg_dcdc3` |
| Một CPU treo cứng giữa lúc systemd khởi động (không đáp IPI backtrace) | `vdd-cpu` thiếu `regulator-ramp-delay`; AXP313A dựng desc bằng `AXP_DESC_RANGES()` → `ramp_delay = 0` → cpufreq nâng xung ngay khi chưa kịp lên áp | DTS: `reg_dcdc2` |
| Màn hình đen dù `[drm] Initialized sun4i-drm` | Tự lấy mode ưa thích của TV = 4K; PHY H616 không chạy nổi TMDS đó | cmdline `video=HDMI-A-1:1920x1080@60` |
| `EMAC reset timeout`, `probe ... failed with error -110` | Ethernet là AC300 EPHY đồng gói, không phải PHY rời. Thiếu `CLK_EMAC_25M` + clock PWM5 (PA12) nên AC300 không chạy → không có REF_CLK → bit reset không bao giờ tự xoá | DTS: `&emac1` kiểu `internal-emac` + `mdio-mux` + `ac300_pwm_clk` |
| Mọi dòng log in đúp | `keep_bootcon` giữ earlycon, cả nó và ttyS0 cùng ghi ra một UART | bỏ khỏi `bootscripts/` |
| `Unsupported Architecture 0x16` | U-Boot 32-bit từ chối uImage gắn thẻ arm64 | script đóng gói dùng `-A arm` |
| initramfs hỏng magic | `bootm` dời ramdisk vào vùng BL31 | `initrd_high=0xffffffff` |
| WiFi: `aicbt_patch_table_alloc fail` | Module `aic8800_bsp_sdio` đọc firmware bằng `filp_open()` (không phải `request_firmware()`), tham số `aic_fw_path` mặc định rỗng và fallback cứng trong Makefile trỏ sai chip (8800D80) | `/etc/modprobe.d/aic8800.conf`: `aic_fw_path=/lib/firmware/aic8800_fw/SDIO/aic8800` (đường dẫn **tuyệt đối**, xem chú thích trong `config/boards/tx68.conf`) |
| BT: `hci0: Opcode 0x1003 failed: -110` (mọi lệnh HCI timeout) | Driver `aic8800_btlpm` cần node DT riêng (`allwinner,sunxi-btlpm`) để bind và điều khiển BT_WAKE/BT_HOSTWAKE; thiếu node này thì chip BT không bao giờ được đánh thức | DTS: node `bt-lpm` (PG17 `bt_wake`, PG16 `bt_hostwake`) |
| BT vẫn không lên dù đã có node `bt-lpm` | GPIO PG16 (`bt_hostwake`, = gpio-208) đã bị driver **UNISOC WCN "marlin"** build sẵn trong kernel (`CONFIG_WCN_BSP_DRIVER_BUILDIN=y`, dành cho chip UWE5622 mà board này không có) giữ mất từ lúc t=2s, trước khi driver của ta kịp nạp — xác nhận bằng `cat /sys/kernel/debug/gpio` thấy `gpio-208` do `bt-wake-host-gpio` giữ | `config/kernel/linux-sunxi64-current.config`: tắt `CONFIG_WCN_BSP_DRIVER_BUILDIN`, `CONFIG_WLAN_UWE5621/5622`, `CONFIG_UNISOC_WIFI_PS` |

### Còn tồn đọng

- Chip WiFi/BT thực tế tự nhận diện qua SDIO là **AIC8801** (chip_rev U03/U04), KHÔNG phải AIC8800DC như tên thư mục driver trong Android BSP gợi ý — xác nhận bằng log SDIO probe trên phần cứng thật (`vid:0x5449 did:0x0145` → `PRODUCT_ID_AIC8801`). WiFi + Bluetooth đã chạy được (xem bảng lỗi ở trên); board TX68 khác có thể báo chip khác, đừng giả định lại mà hãy tra log.
- USB0 (PHY0): mặc định đã ép **host mode** (`&usbotg { dr_mode = "host"; }`), tương đương "tắt" chế độ OTG debug kiểu Android. Đây là giá trị **biên dịch cứng trong DTB**, không có cách chuyển qua lại bằng biến U-Boot bootenv — driver `musb-sunxi`/`dwc2` không lộ sysfs role-switch trên board này (đã kiểm tra `/sys/class/*/role`, không tồn tại). Muốn đổi sang OTG/peripheral phải sửa `dr_mode` trong DTS rồi build lại DTB.
- eMMC tự expand: **đã sửa**. GPT vendor (`phoenix-config/sys_partition.fex`)
  chỉ định nghĩa 1 partition (`rootfs`), nhưng máy thật luôn còn dư một
  partition `userdata` phía sau (rác từ layout Android gốc, PhoenixSuit không
  ghi đè). `armbian-resize-filesystem` bản gốc **cố tình từ chối** resize nếu
  có partition khác nằm sau root (an toàn — tránh xoá nhầm dữ liệu), nên nó
  luôn `disabled` trên board này, rootfs kẹt ở ~5.6 GiB.
  Đã port bản vá của `orangepi-build` (`orangepi-resize-filesystem`, đã test
  trên máy thật): thêm nhánh `BOARD == tx68` vào
  `packages/bsp/common/usr/lib/armbian/armbian-resize-filesystem` — tự xoá
  partition thừa (nếu chưa mount) rồi resize bằng `sfdisk -N <part> ", +"`
  (an toàn cho GPT — cách `fdisk` keystroke cũ chỉ đúng cho MBR, chạy xong mà
  không hề đổi partition GPT, không báo lỗi). Không cần cấu hình gì thêm ở
  `config/boards/tx68.conf`, service `armbian-resize-filesystem` đã tự bật
  cho mọi board.
  ⚠️ Hệ quả: **không còn phân vùng `userdata`/`/data` riêng** — rootfs chiếm
  toàn bộ eMMC, giống hệt orangepi-build/KM7.
- WiFi/BT: **đã chạy được** (SDIO WiFi scan/associate, BT hci0 lên). Chip SDIO
  là AIC8801 chứ không phải AIC8800DC (xem trên). Đã bật `radxa-aic8800` với
  `AIC8800_TYPE="sdio"` trong `config/boards/tx68.conf`; DT có `&mmc1` +
  `wifi_pwrseq` (PG18), node `bt-lpm` (PG16/PG17), và `&uart1` cho BT. **Không**
  bật `uwe5622-allwinner`. Extension này tải .deb từ `github.com/radxa-pkg/aic8800`
  lúc build, cache ở `cache/radxa-aic8800-debs/`.

---

## 7. Cấu trúc thư mục

```
tx68/
├── android-pack/      # khoá + pack_out + pctools vendor (gitignored)
├── uboot-debs/        # gói U-Boot (gitignored)
├── bootscripts/
│   ├── boot-tx68.cmd       # kernel vendor 5.4
│   └── boot-tx68-next.cmd  # kernel mainline  ← đang dùng
├── patches/           # patch cho U-Boot vendor
├── pack-uboot/        # công cụ đóng gói Allwinner (binary x86-64)
├── phoenix-config/    # image.cfg + sys_partition.fex
└── scripts/
    ├── tx68-build-uboot.sh          # bước 2
    └── tx68-build-phoenix-image.sh  # bước 3
```

Các file liên quan ngoài `tx68/`:

- `config/boards/tx68.conf` — profile board của armbian
- `patch/kernel/archive/sunxi-6.18/dt_64/sun50i-h616-tx68.dts` — DTS
- `config/kernel/linux-sunxi64-current.config` — kernel config
