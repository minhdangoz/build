# TX68 / m1k_go — Đặc tả phần cứng

Bảng tra cứu **sự thật phần cứng** cho TV box TX68 (Allwinner H618).

Mục đích: mọi giá trị trong DTS phải truy được về một dòng cụ thể trong nguồn
vendor hoặc một quan sát trên máy thật. Phần lớn thời gian debug của dự án này
bị đốt vào việc **đoán** những con số dưới đây, rồi phát hiện sai sau một chu kỳ
build + flash. Chưa có mục nào ở đây thì đừng viết vào DTS.

Quy trình dựng ảnh nằm ở [`tx68/README.md`](../tx68/README.md); chuỗi secure boot
ở [`docs/SECURE_BOOT.md`](SECURE_BOOT.md). File này chỉ nói **phần cứng là gì**.

---

## Ký hiệu mức tin cậy

| Ký hiệu | Nghĩa |
|---|---|
| ✅ | Đã quan sát trên TX68 thật (log kernel, `/sys`, hoặc hành vi thấy được) |
| 📄 | Lấy từ BSP vendor, chưa tự kiểm trên mainline |
| ❓ | Chưa xác minh — **đọc kỹ ghi chú trước khi dựa vào** |

## Nguồn

| Bí danh dùng bên dưới | Đường dẫn |
|---|---|
| `board.dts` | `/home/jimmy/AOSP/pp618/longan/device/config/chips/h618/configs/m1k_go/linux-5.4/board.dts` |
| `sys_config.fex` | cùng thư mục trên |
| `pack fex` | `tx68/pack-uboot/bin/sys_config/sys_config_tx68.fex` (bản dùng khi đóng gói) |
| BSP wireless | `/home/jimmy/AOSP/pp618/hardware/aic/`, `.../longan/kernel/linux-5.4/drivers/net/wireless/aic8800/` |
| runtime | log UART + `/sys` trên máy thật |

---

## 1. Định danh

| Hạng mục | Giá trị | Nguồn |
|---|---|---|
| Sản phẩm | TX68 | — |
| Board vendor | `m1k_go`, product `vnd_m1k_go` | Android BSP |
| SoC | Allwinner **H618** (4× Cortex-A53) | ✅ `Machine model: TX68`, `0x410fd034` |
| Tên chip BSP | `sun50iw9p1` | 📄 defconfig |
| Compatible mainline | `"oranth,tx68", "allwinner,sun50i-h618"` | — |
| DTSI mainline | `sun50i-h616.dtsi` | Mainline **không có** `sun50i-h618.dtsi`; H618 dùng chung dtsi H616, phân biệt bằng compatible |

---

## 2. CPU · DVFS

| Hạng mục | Giá trị | Nguồn |
|---|---|---|
| Tần số boot (Boot0/U-Boot) | **1008 MHz** | 📄 `sys_config.fex` `[target] boot_clock = 1008` |
| Speed bin eFuse | **speed0** | ✅ `sun50i_cpufreq_nvmem: Using CPU speed bin speed0` |
| OPP khả dụng (speed0) | 480 · 720 · 936 · 1008 · 1104 · 1200 · 1320 · **1416** MHz | ✅ `scaling_available_frequencies` |
| Điện áp ở 1416 MHz | 1100 mV | ✅ `vdd-cpu = 1100000uV` |
| Nhiệt tới hạn CPU | 115 °C | 📄 `board.dts` `cpu_crit` |
| Nhiệt lúc chạy GNOME | ~57 °C | ✅ `/sys/class/thermal` |

> ⚠️ **`regulator-ramp-delay` trên `vdd-cpu` là bắt buộc.** Xem mục 4.

## 3. GPU

| Hạng mục | Giá trị | Nguồn |
|---|---|---|
| GPU | Mali-G31 MP2 | H618 |
| OPP vendor | 306–**600** MHz, toàn dải ở 950 mV | 📄 `board.dts &gpu` |
| Nguồn | `dcdc1` (`vdd-gpu-sys`) | 📄 + ✅ 960 mV lúc chạy |
| Tăng tốc phần cứng | Hoạt động (Panfrost) | ✅ GNOME mượt ở 1080p |

---

## 4. PMIC — AXP1530 (mainline: `x-powers,axp313a`)

Trên bus **`r_i2c`** (vendor `twi5`), pin **PL0/PL1**, địa chỉ **0x36**, 400 kHz.
Không có chân ngắt (`/* irq line nc */` trong `board.dts`) — chỉ `wakeup-source`.

| Rail | Tên | Cấp cho | Vendor cho phép | DTS ta đặt | Nguồn |
|---|---|---|---|---|---|
| dcdc1 | `vdd-gpu-sys` | GPU + SYS | 500–3400 mV | 810–990 mV | ✅ 960 mV |
| dcdc2 | `vdd-cpu` | CPU | 500–1540 mV | 810–1100 mV | ✅ 1100 mV |
| dcdc3 | `vdd-dram` | DRAM | 500–1840 mV | **1500 mV cố định** | ✅ 1500 mV |
| aldo1 | `vcc-1v8` | PLL, bank PC/PG, HDMI, vqmmc | 500–3500 mV | 1800 mV | ✅ |
| dldo1 | `vcc-3v3` | VCC-IO, bank PA/PH/PI, vmmc | 500–3500 mV | 3300 mV | ✅ |

### 4.1 `vdd-dram` phải là 1.5 V

Boot0 huấn luyện DDR3 ở 1.5 V rất lâu trước khi Linux chạy. Vendor để dải
500–1840 mV **rộng có chủ đích** để không thành phần nào lập trình lại nó.

Nếu ghi 1360 mV vào DTS, regulator core sẽ kéo tụt rail đang sống:

```
vdd-dram: Bringing 1500000uV into 1360000-1360000uV
```

**Ghim đúng 1500 mV.**

> 📌 Đính chính. Ban đầu tôi quy RCU stall và HDMI chớp cho chính rail này. **Sai
> cả hai.** RCU stall là do thiếu `regulator-ramp-delay` trên `vdd-cpu` (mục 4.2,
> đã chứng minh bằng test 300 vòng đổi tần số); HDMI chớp là do **cáp hỏng**.
> Việc ghim 1.5 V vẫn đúng, nhưng lý do là "vendor không bao giờ lập trình lại
> rail này", không phải vì nó chữa hai triệu chứng kia. Ba thay đổi đi cùng một
> lần flash thì không quy được công cho ai — đó là bài học, đừng lặp lại.

### 4.2 `vdd-cpu` phải có `regulator-ramp-delay = <200>`

Chính vendor cũng đặt vậy — [`board.dts`, nút `reg_dcdc2`](file:///home/jimmy/AOSP/pp618/longan/device/config/chips/h618/configs/m1k_go/linux-5.4/board.dts):

```dts
regulator-ramp-delay = <200>; /* FIXME */
```

Lý do phải có: cpufreq nâng điện áp rồi **nâng xung ngay**; khoảng chờ ở giữa
hoàn toàn đến từ `_regulator_set_voltage_time()` (`drivers/regulator/core.c`).
Hàm này lấy `constraints->ramp_delay`, rồi `desc->ramp_delay`, rồi **trả về 0**.
Mà descriptor AXP313A dựng bằng `AXP_DESC_RANGES()` — macro này truyền
`_ramp_delay = 0`. Không có giá trị trong DT thì core chờ **0 µs**.

Triệu chứng khi thiếu: một CPU treo cứng giữa lúc systemd khởi động, không có
tick, không đáp cả IPI backtrace (`Sending NMI from CPU 0 to CPUs 3:` rồi im).
**CPU nào chết thay đổi giữa các lần boot** — dấu hiệu rail biên, không phải lỗi
logic.

Xác minh trên máy thật: 300 vòng nhảy 480 ↔ 1416 MHz không treo. ✅

### 4.3 Hai property vendor cần bỏ qua

`regulator-step-delay-us` và `regulator-final-delay-us` xuất hiện trên mọi rail
trong DT vendor. **Không driver nào trong cây 6.18 đọc chúng** — đã grep toàn bộ
`drivers/regulator/`. Đừng chép sang.

---

## 5. DRAM

| Hạng mục | Giá trị | Nguồn |
|---|---|---|
| Loại | **DDR3** (`dram_type = 3`) | 📄 `sys_config.fex` |
| Xung | **648 MHz** (`dram_clk`) | 📄 |
| Điện áp | **1.5 V** | ✅ mục 4.1 |
| Biến thể dung lượng | Có bản **2 GB** và **4 GB** | Yêu cầu dự án |
| Chọn cấu hình theo GPIO | **Tắt** (`select_mode = 0`) | 📄 `[dram_select_para]` |
| Nhiệt DDR lúc chạy | ~56 °C | ✅ |

Có `dram_para1` … `dram_para15` trong fex nhưng `select_mode = 0` nghĩa là
**không** chọn theo GPIO; Boot0 tự dò dung lượng.

> ⚠️ **Bẫy 4 GB.** `dram_init()` của U-Boot vendor (`board/sunxi/board.c`) kẹp
> cứng `dram_size` xuống 2048 MiB. Kích thước thật Boot0 dò được nằm ở
> `uboot_spare_head.boot_data.dram_scan_size` (MiB). Patch
> `tx68/patches/0003-*` đọc giá trị này và vá lại node `/memory` cho Linux.
> Máy 2 GB không đi qua nhánh đó. Xem mục 12.

---

## 6. Lưu trữ

### 6.1 eMMC — `mmc2` @ 0x04022000 ✅

| Hạng mục | Giá trị | Nguồn |
|---|---|---|
| Bus | 8-bit, non-removable | 📄 `[card2_boot_para] card_line = 8` |
| Tốc độ vendor | HS400 1.8 V @ 100 MHz | 📄 + ✅ U-Boot: `Best spd md: 4-HS400` |
| Tốc độ mainline dùng | **DDR52 @ 52 MHz** — cố ý không HS200 | xem cảnh báo dưới |

> ⚠️ **Không bật `mmc-hs200-1_8v`.** HS200 cần tuning CMD21, mà `sunxi-mmc`
> **không cài `mmc_host_ops.execute_tuning`** — nên `mmc_execute_tuning()` trả về
> thành công một cách im lặng và HS200 chạy không tuning, chỉ dựa vào auto-calib
> phần cứng. Biên độ khi đó phụ thuộc con eMMC được hàn:
>
> | eMMC | HS200 @100 MHz |
> |---|---|
> | `HAG4a2` 14.7 GiB | chạy ổn |
> | `CJNB4R` 58.2 GiB | `data error, sending stop command` liên tục, rồi mọi `execve()` kẹt ở `d_alloc_parallel` → `khungtaskd` panic |
>
> Hầu như không board H616 nào khác trong cây bật HS200 (`bigtreetech-cb1-emmc`
> và `sovol-sv08` còn dùng `no-1-8-v`, sovol cap 45 MHz). Ngoại lệ duy nhất là
> `x96-mate` — cũng chính là board đã khiến phần Ethernet bị chép sai. **Đừng lấy
> nó làm chuẩn.**
| Dung lượng | **Thay đổi theo board** | ✅ đã gặp 14.7 GiB (`HAG4a2`) và 58.2 GiB (`CJNB4R`) |

> ⚠️ **GPT vendor chia sẵn 2 partition sát nhau** (`phoenix-config/sys_partition.fex`):
> rootfs (~5.7 GiB) rồi tới `userdata` (phần còn lại, ví dụ 52.5 GiB trên
> board 58.2 GiB). `armbian-resize-filesystem` chỉ mở rộng được vào khoảng
> trống *chưa phân vùng* — ở đây không có, nên rootfs **không tự lớn ra**, và
> service resize luôn ở trạng thái `disabled` (đúng thiết kế, không phải lỗi).
> Đã thêm service `tx68-userdata-mount` (đóng gói qua
> `post_family_tweaks__tx68`) tự format ext4 + mount partition 2 vào `/data`
> ở lần boot đầu, thay vì để trống phí. Muốn rootfs lớn hơn thật sự phải sửa
> lại GPT trong `phoenix-config/sys_partition.fex` — **chưa làm**, vì đụng cấu
> trúc phân vùng vendor, cần cân nhắc riêng trước khi động vào.

> ⚠️ **Không được hardcode `root=/dev/mmcblk0p1`.** Linux đánh số host MMC theo
> **thứ tự probe**, không theo địa chỉ controller. TX68 có hai host: eMMC
> (`mmc@4022000`) và SDIO WiFi (`mmc@4021000`). Cái nào probe xong trước lấy
> index 0, nên eMMC lúc là `mmcblk0`, lúc là `mmcblk1`:
>
> ```
> mmc0: new SDIO card at address a281
> mmc1: new HS200 MMC card at address 0001
> mmcblk1: mmc1:0001 CJNB4R 58.2 GiB
> ...
> ALERT!  /dev/mmcblk0p1 does not exist.  Dropping to a shell!
> ```
>
> Trước khi bật WiFi thì eMMC là host duy nhất nên index 0 luôn đúng và lỗi này
> vô hình. Boot script dùng `root=PARTUUID=${partuuid}` lấy từ chính bảng phân
> vùng GPT — miễn nhiễm với cách Linux đánh số.
| vmmc / vqmmc | `dldo1` (3.3 V) / `aldo1` (1.8 V) | 📄 |
| Bank PC | **1.8 V** | 📄 `[gpio_bias] pc_bias = 1800` |

Sơ đồ chân (📄 `[card2_boot_para]`):

| Tín hiệu | Chân | | Tín hiệu | Chân |
|---|---|---|---|---|
| CLK | PC5 | | D4 | PC9 |
| CMD | PC6 | | D5 | PC11 |
| D0 | PC10 | | D6 | PC14 |
| D1 | PC13 | | D7 | PC16 |
| D2 | PC15 | | RST | PC1 |
| D3 | PC8 | | DS (HS400) | PC0 |

### 6.2 Thẻ SD — `mmc0` @ 0x04020000 ❓

Vendor **có** bật `&sdc0`: 4-bit trên PF0–PF5, card-detect **PI16** active low,
UHS SDR50/DDR50/SDR104.

Nhưng TX68 được mô tả là **không có khe microSD**. DT vendor dùng chung cho
nhiều SKU của `m1k_go`, nên rất có thể khe này không được hàn. DTS mainline của
ta hiện **không bật** `mmc0`. Nhìn vào vỏ máy trước khi bật.

---

## 7. Ethernet — AC300 EPHY, **không phải** PHY rời ⚠️

Đây là chỗ tốn nhiều công nhất. Đọc kỹ.

| Hạng mục | Giá trị | Nguồn |
|---|---|---|
| MAC | `emac1` @ 0x05030000 (`gmac0` **tắt**) | 📄 |
| PHY | **AC300**, đồng gói trong H618 | mainline `sun50i-h618-orangepi-zero2w.dts` |
| Chế độ | RMII | 📄 `phy-mode = "rmii"` |
| Chân RMII | **PA0–PA9**, function `emac1` | 📄 `gmac1_pins_a` |
| Clock 1 | `CLK_EMAC_25M` (CCU gate 0x970) | mainline |
| Clock 2 | **PWM5 trên PA12 → 2 MHz** | 📄 `pwm5_pin_a` + `&pwm5 status okay` |
| Hiệu chuẩn | eFuse `sid` offset **0x2c**, dài 2 byte | ✅ `Read AC300 EPHY calibration from nvmem: 0x0505` |
| Tốc độ | 100 Mbps | AC300 |
| Tên interface | **`end0`** (không phải `eth0`) | ✅ `end0: renamed from eth0` |

Khi đúng, log phải có đủ bốn dòng này:

```
Allwinner AC300 EPHY mdio_mux-0.1:00: Read AC300 EPHY calibration from nvmem: 0x0505
dwmac-sun8i 5030000.ethernet: Found internal PHY node
dwmac-sun8i 5030000.ethernet: Switch mux to internal PHY
dwmac-sun8i 5030000.ethernet: Powering internal PHY
```

> 🔌 **Kiểm tra phần cứng trước khi debug phần mềm.** Có những board TX68 mà cổng
> Ethernet **chết vì lỗi mạch điện** — đã gặp thật: một board không bao giờ lên
> mạng, board thứ hai cùng ảnh thì chạy ngay. Linux vẫn nhận MAC và tạo interface
> trên board hỏng, vì MAC nằm trong SoC. Nếu ai đó báo Ethernet không chạy, hỏi
> đổi board hoặc thử board khác **trước** khi soi DTS.

AC300 cần **cả hai** clock mới bắt đầu phát REF_CLK 50 MHz ngược vào MAC.

Nếu mô tả nó như PHY rời (`phy-handle` trỏ thẳng vào `mdio1`, giữ compatible mặc
định `allwinner,sun50i-h616-emac`) thì DTS vẫn biên dịch, driver vẫn probe,
nhưng **không clock nào được xin** → AC300 nằm im → không có REF_CLK → bit reset
mềm trong `EMAC_BASIC_CTL1` không bao giờ tự xoá:

```
dwmac-sun8i 5030000.ethernet: EMAC reset timeout
dwmac-sun8i 5030000.ethernet: probe with driver dwmac-sun8i failed with error -110
```

Lỗi xảy ra **trước khi** driver đụng tới PHY — nên nó không hề giống lỗi PHY, và
đó là lý do rất dễ đi lạc.

> 🚫 **Đừng chép `&emac1` từ `sun50i-h616-x96-mate.dts` hay
> `sun50i-h313-x96q-lpddr3.dts`.** Hai TV box đó có PHY RMII rời thật trên bus
> MDIO. Board đúng để đối chiếu là **`sun50i-h618-orangepi-zero2w.dts`** (cùng
> H618 + AC300), hoặc `sun50i-h618-bananapi-m4-zero.dts`.

Cần đủ bộ: `compatible = "allwinner,sun50i-h616-internal-emac"`, `mdio-mux` +
`internal_mdio` + `ac300_ephy`, node `pwm-clock` trên `&pwm 5`, bật `&pwm` và
`&pwm5` (`clk_bypass_output = <1>`), và cell nvmem `ephy_calibration`.

---

## 8. WiFi / Bluetooth — chip thật là AIC8801, không phải AIC8800DC ✅

Tên thư mục BSP Android (`hardware/aic/{wlan,libbt}/firmware/aic8800/aic8800dc`,
driver `longan/kernel/linux-5.4/drivers/net/wireless/aic8800/`) khiến ban đầu
đoán chip là **AIC8800DC**. **Sai.** Bằng chứng trên phần cứng thật, đọc từ log
SDIO probe của chính driver DKMS:

```
aicbsp: aicbsp_sdio_probe:1 vid:0x5449  did:0x0145
```

`0x5449:0x0145` là `SDIO_VENDOR_ID_AIC8801` / `SDIO_DEVICE_ID_AIC8801` trong
`aicwf_sdio.h` của driver — khớp **AIC8801**, `chip_rev` U03/U04, không phải
DC. AIC8800 là một họ chip nhiều biến thể (8801, DC, D80, D80N, D80X2...),
board TX68 khác có thể gắn biến thể khác — **đừng giả định lại, đọc log**
`aicbsp_sdio_probe` mỗi lần gặp board mới.

> 🚫 **Không phải UWE5622.** Các board H618 khác trong cây armbian bật
> `uwe5622-allwinner` — sai chip với TX68, đã loại trên máy thật. Kernel
> `.config` còn build sẵn (`=y`, không phải module) driver UNISOC WCN "marlin"
> cho đúng chip UWE5622 này — **phải tắt**, xem cảnh báo GPIO bên dưới.

| Tín hiệu | Chân | Cực | Nguồn |
|---|---|---|---|
| WL_REG_ON | **PG18** | active high | 📄 `wlan_regon` |
| WL_HOST_WAKE | **PG15** | active high | 📄 `wlan_hostwake` |
| BT_RST | **PG19** | active **low** | 📄 `bt_rst_n` |
| BT_WAKE | **PG17** | active high | 📄 `btlpm bt_wake` |
| BT_HOST_WAKE | **PG16** | active high | 📄 `btlpm bt_hostwake` |
| Clock 32 kHz | ngõ ra LOSC trên **PG10** | 📄 `clk_losc_pins_a` |

| Hạng mục | Giá trị | Nguồn |
|---|---|---|
| Bus SDIO | `mmc1` @ 0x04021000, 4-bit | 📄 `wlan_busnum = 1` |
| Tần số tối đa | 150 MHz | 📄 |
| vmmc / vqmmc | `dldo1` (3.3 V) / `aldo1` (1.8 V) | 📄 |
| Điện áp bus | **1.8 V cố định** | 📄 bank PG ở 1.8 V + `sunxi-dis-signal-vol-sw` |
| UART Bluetooth | **uart1** (PG6/PG7 + RTS/CTS PG8/PG9) | 📄 `btlpm uart_index = 1` |

Ghi chú clock 32 kHz: mainline **không có** nhóm pinctrl `x32kfout`. Không cần —
`<&rtc 1>` (`CLK_OSC32K_OUT`) tự bật pad. Các board zero2w/zero3 làm y hệt.

Driver: gói DKMS `radxa-pkg/aic8800` (`AIC8800_TYPE="sdio"`), dựng ba module
`aic8800_bsp_sdio`, `aic8800_fdrv_sdio`, `aic8800_btlpm_sdio`. Build sạch, 0 lỗi
— không cần port từ 5.4. **Đã chạy được WiFi + Bluetooth trên phần cứng thật**
(WiFi scan/associate ra IP; BT `hci0` lên, HCI command trả lời), sau khi vá ba
lỗi sau — cả ba chỉ lộ ra khi đọc thẳng mã nguồn DKMS
(`SDIO/driver_fw/driver/aic8800/`), không có cách nào đoán được:

1. **`aicbt_patch_table_alloc fail`** — module `aic8800_bsp_sdio` đọc firmware
   BT patch-table bằng `filp_open()` (không phải `request_firmware()`, vì
   `CONFIG_USE_FW_REQUEST` không bật trong build này), dùng tham số module
   `aic_fw_path`. Tham số này **mặc định rỗng** — fallback cứng trong Makefile
   của driver (`CONFIG_AIC_FW_PATH`) chỉ trỏ đúng cho chip 8800D80, sai board
   này. Phải set tường minh qua `modprobe.d`, và **phải là đường dẫn tuyệt
   đối** (khác quy ước `/lib/firmware`-relative dùng ở chỗ khác trong cùng
   driver) — dùng đường dẫn tương đối kiểu `aic8800_fw/SDIO/aic8800` sẽ vẫn
   fail y hệt vì `filp_open()` không tự thêm `/lib/firmware/`:
   ```
   # /etc/modprobe.d/aic8800.conf
   options aic8800_bsp_sdio aic_fw_path=/lib/firmware/aic8800_fw/SDIO/aic8800
   ```
2. **`hci0` lên nhưng mọi lệnh HCI timeout** (`Opcode 0x1003 failed: -110`) —
   driver `aic8800_btlpm_sdio` là một `platform_driver` riêng, khớp
   `compatible = "allwinner,sunxi-btlpm"` (tự đặt ra, **không phải** binding
   mainline), cần node DT của chính nó với hai GPIO `bt_wake` (PG17) và
   `bt_hostwake` (PG16) để đánh thức BT core trước khi UART có phản hồi. DTS
   ban đầu cố tình không có node "bluetooth" nào (đúng, vì không có serdev
   compatible mainline) nhưng quên rằng driver này cần một node **root-level**
   riêng, không phải serdev con của `&uart1`. Thiếu node này thì
   `platform_driver_probe()` fail, không tạo `/proc/bluetooth/sleep/btwrite`,
   BT_WAKE không bao giờ được toggle. Xem node `bt-lpm` trong DTS.
3. **Vẫn timeout dù đã thêm node `bt-lpm`** — GPIO PG16 (`bt_hostwake`, =
   `gpio-208`, xem bank/offset ở §13) đã bị driver UNISOC WCN "marlin" (built
   sẵn `=y` trong kernel cho chip UWE5622, KHÔNG phải chip board này có) giữ
   từ giây thứ 2 lúc boot — xác nhận bằng
   `cat /sys/kernel/debug/gpio | grep gpio-208` thấy consumer
   `bt-wake-host-gpio`. `aic8800_btlpm`'s `devm_gpio_request()` fail với
   `-EBUSY` nhưng lỗi này bị nuốt vì `BT_ERR`/`BT_DBG` trong driver đều là
   `pr_debug()` — im lặng hoàn toàn trừ khi bật dynamic debug. Sửa ở
   `config/kernel/linux-sunxi64-current.config`:
   `CONFIG_WCN_BSP_DRIVER_BUILDIN`, `CONFIG_WLAN_UWE5621`,
   `CONFIG_WLAN_UWE5622`, `CONFIG_UNISOC_WIFI_PS` — tất cả tắt.

Cả `/etc/modprobe.d/aic8800.conf` và service `aic8800-bluetooth.service`
(`hciattach ... /dev/ttyS1`) được đóng gói tự động qua hook
`post_family_tweaks__tx68` trong `config/boards/tx68.conf`, không cần làm tay.

---

## 9. Hiển thị

| Hạng mục | Giá trị | Nguồn |
|---|---|---|
| HDMI | DesignWare **v2.12a**, có HDCP | ✅ log |
| Nguồn HDMI | `aldo1` (1.8 V) + `dcdc1` | 📄 `hdmi_power0/1` |
| CEC | vendor **tắt** (`hdmi_cec_support = 0`) | 📄 |
| Mode TV đang dùng chào ra | 3840x2160 (×10), 2560x1440, 1920x1080 | ✅ `/sys/class/drm/card0-HDMI-A-1/modes` |
| Mode nên dùng | **1920x1080@60** | ✅ 4K lên được nhưng quá giật |
| CVBS / TV out | vendor bật `&tv0`, `interface = 1` | 📄 ❓ chưa thử trên mainline |

`sun8i_dw_hdmi_mode_valid_h6()` chỉ chặn trên 594 MHz nên 4K@60 vẫn được chào ra.
Ghim mode bằng cmdline `video=HDMI-A-1:1920x1080@60` trong boot script — knob
kernel, đổi không cần dựng lại DTB hay kernel.

> Bài học: màn hình đen ban đầu **là do cáp HDMI hỏng**, không phải 4K. Đổi cáp
> trước khi nghi phần mềm.

---

## 10. Âm thanh

| Ngõ | Chân | Trạng thái |
|---|---|---|
| Codec analog (Line Out) | — | ✅ `#0: h616-audio-codec` |
| HDMI audio | — | qua `&hdmi` |
| SPDIF | PH4 | 📄 ❓ chưa bật ở mainline |
| I2S0 | PA6–PA9 | 📄 ⚠️ **đụng chân Ethernet** |
| I2S2 | PG11/PG12, DOUT PG13 | 📄 |
| I2S3 | PH5–PH7, DOUT PH8 | 📄 ⚠️ đụng SPI1 |

---

## 11. Ngoại vi khác

| Khối | Chi tiết | Nguồn |
|---|---|---|
| UART debug | **uart0**, PH0/PH1, 115200 8N1 | ✅ |
| IR | **PH10**; power key `0x4d` addr `0x4040`, và `0x51` addr `0x7f80` | 📄 + ✅ `sunxi-ir` probe |
| USB | usbc0–3 đều bật; vendor để usbc0 là **device** (`usb_port_type = 0`) | 📄 |
| | DTS ta đặt `dr_mode = "host"` — **khác vendor có chủ đích**, giống `x96-mate` | ✅ chuột/bàn phím chạy |
| **VBUS cổng PHY0** | GPIO **PH8**, active high | 📄 vendor `usb0_drvvbus`, dùng bởi cả `&ehci0` và `&ohci0` |

> Thiếu regulator PH8 thì cổng USB trên PHY0 **không bao giờ có 5 V** — không thiết
> bị nào enumerate ở đó. Ba cổng còn lại vẫn chạy bình thường, nên rất dễ không
> nhận ra. Bank PH ở 3.3 V nên `enable-active-high` là đúng.

> ⚠️ **`dr_mode = "host"` là biên dịch cứng trong DTB, không có runtime toggle.**
> Đã kiểm tra: không có sysfs role-switch nào (`/sys/class/*/role`) tồn tại
> trên board này cho controller usbotg (musb-sunxi) — đây không phải thiếu sót,
> mainline driver cho SoC này chỉ hỗ trợ role cố định theo `dr_mode`, không hỗ
> trợ USB Role Switch framework. Muốn đổi giữa host/OTG-device phải sửa
> `dr_mode` trong `&usbotg` của DTS rồi build lại DTB (§4 trong README) — không
> có cách nào làm qua U-Boot bootenv hay kernel cmdline.

### 11.1 `vcc-pX-supply` là an toàn, không phải trang trí

`sunxi_pinctrl_set_io_bias_cfg()` (`drivers/pinctrl/sunxi/pinctrl-sunxi.c`) **ghi
thẳng vào thanh ghi chọn chế độ nguồn của PIO** theo điện áp đọc được từ
regulator: `val = uV <= 1800000 ? 1 : 0`, mỗi bank một bit. H616 dùng variant
`BIAS_VOLTAGE_PIO_POW_MODE_CTL`. Khai sai một bank là toàn bộ IO của bank đó chạy
sai mức.

| Bank | Rail | Bằng chứng |
|---|---|---|
| PA | dldo1 3.3 V | ✅ RMII PA0–PA9 chạy |
| PC | aldo1 1.8 V | 📄 `[gpio_bias] pc_bias = 1800` |
| PG | aldo1 1.8 V | 📄 `vcc-pg-supply = <&reg_pio1_8>` |
| PH | dldo1 3.3 V | ✅ console UART0 PH0/PH1 chạy |
| PI | dldo1 3.3 V | ❓ chưa dùng chân PI nào |
| SPI0 / SPI1 | vendor **tắt** cả hai | 📄 |
| TWI0–TWI4 | vendor **tắt** hết | 📄 |
| Standby | `standby_mode = 1` | 📄 |

---

## 12. Bản đồ bộ nhớ & secure boot

| Vùng | Địa chỉ | Ghi chú |
|---|---|---|
| Gốc DRAM | `0x40000000` | |
| `secmon` (dtsi) | `0x40000000`, 512 KiB | Chỗ ATF **mainline** ở — TX68 không chạy ATF mainline |
| **BL31 + OP-TEE vendor** | `0x48000000`, **16 MiB** | ⚠️ dtsi mainline **không** khai; phải tự thêm |
| U-Boot vendor nạp tại | `0x4a000000` | Banner BL31 |

Thiếu node `bl31@48000000` trong DTS thì Linux coi vùng đó là RAM trống và cấp
phát đè lên secure monitor đang chạy → hỏng bộ nhớ và Oops ngẫu nhiên hoàn toàn
không liên quan (đã gặp: dentry có superblock NULL lúc probe i2c). ✅ đã sửa.

BL31 bàn giao cho U-Boot ở **AArch32 SVC** (`spsr = 0x1d3`) — vì thế U-Boot
vendor là 32-bit và **không thể** thay bằng U-Boot mainline (AArch64). Chi tiết ở
[`docs/SECURE_BOOT.md`](SECURE_BOOT.md).

### ❓ Chưa giải quyết: `dram_region_mbytes = 80`

`[secure]` trong `sys_config.fex` khai vùng DRAM bảo mật **80 MiB**, trong khi ta
mới giữ 16 MiB tại `0x48000000`. Chưa xác định 80 MiB đó nằm ở đâu và có phải
toàn bộ đều đang được dùng hay không.

Hiện tại hệ thống ổn định với 16 MiB (Oops đã hết hẳn), nên nhiều khả năng phần
còn lại không được truy cập. **Nhưng đây vẫn là rủi ro chưa loại trừ** — nếu sau
này gặp hỏng bộ nhớ ngẫu nhiên, hãy quay lại chỗ này trước tiên.

---

## 13. Xung đột chân — đọc trước khi bật thêm gì

| Chân | Bên A | Bên B | Ai thắng |
|---|---|---|---|
| PA6–PA9 | Ethernet RMII | I2S0 | **Ethernet** |
| PA12 | Clock AC300 (PWM5) | PWM5 dùng chung | Ethernet cần nó |
| PG15/PG16 | WL_HOST_WAKE / BT_HOST_WAKE | TWI4 | **WiFi/BT** (TWI4 tắt) |
| PG16 (`gpio-208`) | BT_HOST_WAKE (node `bt-lpm`) | Driver marlin/UWE5622 built-in kernel | **WiFi/BT** — phải tắt `CONFIG_WCN_BSP_DRIVER_BUILDIN`, xem §8 mục 3 |
| PG17/PG18 | BT_WAKE / WL_REG_ON | TWI3 | **WiFi/BT** (TWI3 tắt) |
| PH5–PH8 | I2S3 | SPI1 | cả hai đang tắt |
| PI16 | Card-detect thẻ SD | `select_gpio2` của dram_select | dram_select tắt (`mode 0`) |

---

## 14. Việc còn lại

| Hạng mục | Trạng thái |
|---|---|
| Ethernet AC300 | ✅ PHY lên, `end0` xuất hiện — chưa test lưu lượng thật |
| WiFi | ✅ **hoạt động** — scan, associate, ra IP. Chip thật AIC8801, xem §8 |
| Bluetooth | ✅ **hoạt động** — `hci0` lên, HCI trả lời. Cần node `bt-lpm` + tắt driver marlin, xem §8 |
| X11 mặc định | ✅ GDM ép Xorg (`WaylandEnable=false`) qua `post_family_tweaks__tx68` |
| Console/desktop full auto-login | ✅ `DESKTOP_AUTOLOGIN` + `CONSOLE_AUTOLOGIN` đều `"yes"` trong `config/boards/tx68.conf` |
| eMMC partition 2 (`userdata`) | ✅ tự format + mount `/data` qua service `tx68-userdata-mount` |
| USB0 host/OTG toggle | ❌ không có runtime toggle, biên dịch cứng trong DTB — xem §11 |
| Khe thẻ SD | ❓ chưa rõ có tồn tại vật lý |
| CVBS (`tv0`) | ❓ chưa thử |
| SPDIF | ❓ chưa bật |
| Vùng secure 80 MiB | ❓ xem mục 12 |
| eMMC HS400 | Vendor chạy HS400; mainline dùng **DDR52 @ 52 MHz** (không phải HS200 — xem cảnh báo §6.1) |
| eMMC rootfs không tự lớn | GPT vendor không chừa khoảng trống — xem cảnh báo §6.1. Muốn sửa tận gốc phải đổi `phoenix-config/sys_partition.fex` |
| XFCE | Chưa làm — GNOME vẫn là DE mặc định, chỉ ép X11 |
