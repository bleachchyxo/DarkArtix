#!/bin/bash
# Simple mount script assuming user provides disk

set -e

main_disk="/dev/vda"
#main_disk="/dev/sdb"

# Mount root partition
mount "${main_disk}2" /mnt

# Create directories for boot and home
mkdir -p /mnt/boot /mnt/home

# Mount boot and home partitions
mount "${main_disk}1" /mnt/boot
mount "${main_disk}3" /mnt/home

echo "Partitions mounted successfully:"
