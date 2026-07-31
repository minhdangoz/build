# Giải thích đơn giản

## U-Boot là gì?
U-Boot là chương trình khởi động, chạy **trước** khi Linux bắt đầu. Nhiệm vụ của nó: đọc kernel từ eMMC, nạp vào RAM, rồi nhảy vào kernel.

Chuỗi khởi động của TX68:
```
BootROM → Boot0 → BL31 → U-Boot → Linux
                   ↑
            (chỗ quan trọng)
```

## Vấn đề gốc rễ

TX68 có **secure boot** (khởi động bảo mật): chip chỉ chạy code đã ký bằng khóa của nhà sản xuất.

Từ log UART của anh có dòng này:
```
Next image spsr = 0x1d3
```

Giải mã `0x1d3` ra: **BL31 khởi chạy U-Boot ở chế độ 32-bit (AArch32)**.

Đây chính là câu trả lời cho câu hỏi của anh. Vì BL31 chạy U-Boot ở 32-bit, nên **bắt buộc phải dùng U-Boot 32-bit của nhà sản xuất** (bản 2018 cũ). Không phải tôi chọn, mà là phần cứng ép buộc.

## U-Boot cũ này thiếu gì?

| Mainline U-Boot (Zero 3 dùng) | U-Boot vendor (TX68 bắt buộc dùng) |
|---|---|
| 64-bit | **32-bit** |
| Có lệnh `booti` | Không có, chỉ có `bootm` |
| Nhận file DTB mình nạp vào | **Bỏ qua**, luôn dùng DTB nhúng sẵn bên trong nó |
| Nhận nhãn `ARM64` | Chỉ nhận nhãn `ARM` |

Zero 3 chạy ngon vì nó dùng mainline U-Boot — không bị mấy hạn chế trên.

## Tôi đã sửa gì (5 lỗi, cùng 1 nguyên nhân)

1. **Địa chỉ nạp** — kernel mới 38MB đè lên DTB và initrd đã nạp trước đó → đổi địa chỉ cho cách xa nhau
2. **Không có `booti`** → bọc kernel thành uImage, dùng `bootm`
3. **DTB bị bỏ qua** → build lại U-Boot, nhúng DTB mainline của TX68 vào trong chính nó
4. **Nhãn kernel** `arm64` → `arm`
5. **Nhãn initrd** `arm64` → `arm` (lỗi cuối, vừa sửa xong)

Cả 5 lỗi đều do **1 nguyên nhân duy nhất**: U-Boot 32-bit. Lỗi của tôi là không giải mã `spsr` ngay từ đầu để thấy điều đó, mà đi sửa từng triệu chứng một — làm anh mất nhiều lần nạp firmware.

## Tại sao chưa dùng mainline U-Boot?

Vì phải **thay luôn BL31**, để nó khởi chạy U-Boot ở chế độ 64-bit.

Tin tốt: việc này **làm được**, vì:
- Mình có đủ khóa ký của nhà sản xuất
- File `dragon_toc.cfg` cho phép ký riêng từng phần: `monitor` (BL31), `optee`, `u-boot`
- Địa chỉ **khớp chính xác**: mainline U-Boot dùng `0x4a000000`, đúng bằng địa chỉ mà chuỗi secure boot của TX68 bàn giao

Làm xong cái này thì TX68 sẽ chạy giống hệt Zero 3, và xóa được toàn bộ 5 chỗ vá tạm ở trên.

## Bước tiếp theo

Anh nạp thử file này trước (tôi đã kiểm tra bên trong, cả 3 phần đều đúng nhãn `ARM`):

```
/media/jimmy/WORK/AOSP/build/output/phoenix/
Armbian-unofficial_26.08.0-trunk_Tx68_noble_current_6.18.41_gnome_desktop_20260730_23-10-32_phoenixsuite.img
```

Nếu boot được, mình có bản chạy ổn định làm nền, rồi mới chuyển sang mainline U-Boot — có đường lùi an toàn. Anh muốn tôi bắt đầu làm phần mainline BL31 song song luôn không?