#!/bin/bash
set -euo pipefail

firmware_type="BIOS"
[ -d /sys/firmware/efi ] && firmware_type="UEFI"

disk="/dev/sdb"
disk_name=$(basename "$disk")
total_gb=$(( $(< /sys/block/$disk_name/size) * $(< /sys/block/$disk_name/queue/hw_sector_size) / 1024 / 1024 / 1024 ))

case $total_gb in
  [0-9]) boot_size=0.5 root_size=4 ;;
  1[0-9]) boot_size=0.5 root_size=6 ;;
  2[0-9]|3[0-9]) boot_size=1 root_size=8 ;;
  [4-9][0-9]) boot_size=1 root_size=20 ;;
  1[0-9][0-9]|*) boot_size=1 root_size=30 ;;
esac

echo "→ Firmware: $firmware_type"
echo "→ Disk: ${total_gb}G"
echo "→ Layout: /boot=${boot_size}G  /=${root_size}G  /home=remaining"

fdisk "$disk" <<EOF
o
n
p
1

+${boot_size}G
n
p
2

+${root_size}G
n
p
3


w
EOF

sleep 2

echo "→ Formatting partitions..."
if [ "$firmware_type" = "UEFI" ]; then
  mkfs.fat -F32 "${disk}1"
else
  mkfs.ext4 -F "${disk}1"
fi
mkfs.ext4 -F "${disk}2"
mkfs.ext4 -F "${disk}3"

echo "→ Partitioning and formatting complete."
fdisk -l "$disk" | grep "$disk"
