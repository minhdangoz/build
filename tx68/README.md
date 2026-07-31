# Build TX68 (Allwinner H618)

Hướng dẫn build ảnh Linux mainline cho TV box TX68 / m1k_go.

Nền tảng lý thuyết (vì sao phải dùng U-Boot vendor, secure boot hoạt động ra sao)
nằm ở [`docs/SECURE_BOOT.md`](../docs/SECURE_BOOT.md). File này chỉ nói **cách làm**.

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

Không có chúng thì không ký được TOC1 → máy không boot. Đây là thứ duy nhất
không thể tái tạo từ repo này.

### Nguồn U-Boot vendor

Mặc định đọc từ `/media/jimmy/WORK/AOSP/orangepi-build/u-boot/v2018.05-h618`
(chỉ đọc, không ghi). Đổi bằng biến `TX68_UBOOT_SRC`.

### Công cụ host

```bash
sudo apt install gcc-arm-linux-gnueabi device-tree-compiler \
                 e2fsprogs u-boot-tools rsync busybox dos2unix xxd jq
```

---

## 3. Quy trình build

### Bước 1 — Kernel, DTB, rootfs (armbian)

```bash
cd /media/jimmy/WORK/AOSP/build
./compile.sh \
  BOARD=tx68 \
  BRANCH=current \
  RELEASE=noble \
  BUILD_DESKTOP=yes \
  DESKTOP_ENVIRONMENT=gnome \
  KERNEL_CONFIGURE=no
```

> Đừng chạy bằng `sudo` — armbian tự xin quyền khi cần.

Kết quả: `output/images/Armbian-unofficial_..._gnome_desktop.img`

Lưu ý `DESKTOP_TIER` mặc định là `mid` khi chạy không tương tác, nên rootfs khá to
(~5.7 GB). Đặt `DESKTOP_TIER=minimal` nếu muốn nhỏ hơn.

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
| RCU stall CPU 2/3, HDMI chớp liên tục | DTS ép `dcdc3` xuống 1.36 V trong khi DDR3 chạy 1.5 V | DTS: `reg_dcdc3` |
| Một CPU treo cứng giữa lúc systemd khởi động (không đáp IPI backtrace) | `vdd-cpu` thiếu `regulator-ramp-delay`; AXP313A dựng desc bằng `AXP_DESC_RANGES()` → `ramp_delay = 0` → cpufreq nâng xung ngay khi chưa kịp lên áp | DTS: `reg_dcdc2` |
| Màn hình đen dù `[drm] Initialized sun4i-drm` | Tự lấy mode ưa thích của TV = 4K; PHY H616 không chạy nổi TMDS đó | cmdline `video=HDMI-A-1:1920x1080@60` |
| Mọi dòng log in đúp | `keep_bootcon` giữ earlycon, cả nó và ttyS0 cùng ghi ra một UART | bỏ khỏi `bootscripts/` |
| `Unsupported Architecture 0x16` | U-Boot 32-bit từ chối uImage gắn thẻ arm64 | script đóng gói dùng `-A arm` |
| initramfs hỏng magic | `bootm` dời ramdisk vào vùng BL31 | `initrd_high=0xffffffff` |

### Còn tồn đọng

- `dwmac-sun8i: EMAC reset timeout` — Ethernet chưa lên. Cấu hình (`emac1`, `rmii`)
  đã khớp DT vendor, chưa rõ nguyên nhân.
- WiFi/BT chưa làm. Chip thật là AIC8800 (SDIO), **không phải** UWE5622 mà
  `orangepizero3.csc` bật — đừng bật `uwe5622-allwinner`.

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
