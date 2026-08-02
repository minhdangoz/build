# KM7 Amlogic W1 Bluetooth runtime

The KM7's W1 controller does not answer standard HCI commands until its ICCM
and DCCM firmware has been uploaded over UART. Generic `hciattach` can create
`hci0`, but every command then times out because it does not perform that
vendor initialization.

These files are copied without modification from the matching KM7 Android
tree at `/media/jimmy/WORK/AOSP/s905y4`:

- `vendor/oranth/vendor/bin/aml_bt_hciattach`
- `vendor/oranth/vendor/etc/fw_out.bin` and `fw_out.info`
- the 32-bit Bionic linker and its direct runtime libraries from
  `out/target/product/oppen/recovery/root/system`

`km7-bluetooth.service` invokes the Android executable through that private
linker/runtime. It does not install Bionic into `/system` or replace any host
Ubuntu library.

Live hardware verification on 2026-08-02 produced controller
`6C:05:D3:B2:18:3C` with powered BR/EDR and LE and successfully discovered
nearby devices while the KM7 remained reachable over Ethernet.
