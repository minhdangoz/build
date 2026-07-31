#!/bin/bash
# TX68 vendor GPT (phoenix-config/sys_partition.fex) reserves a second eMMC
# partition ("userdata", ~52 GiB on the 58 GiB module) that armbian-resize-
# filesystem cannot grow rootfs into -- it sits immediately after rootfs with
# no gap, and shrinking/deleting it is not this service's job. Instead, give
# it a filesystem (once) and mount it at /data so the space is usable.
set -e

root_disk="$(lsblk -no PKNAME "$(findmnt -no SOURCE /)" 2> /dev/null)"
[ -n "${root_disk}" ] || exit 0
part="/dev/${root_disk}p2"
[ -b "${part}" ] || exit 0

mountpoint -q /data && exit 0

if ! blkid "${part}" > /dev/null 2>&1; then
	mkfs.ext4 -q -L data "${part}"
fi

mkdir -p /data
grep -q "^LABEL=data " /etc/fstab || echo "LABEL=data /data ext4 defaults 0 2" >> /etc/fstab
mount /data
