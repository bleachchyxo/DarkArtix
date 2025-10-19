#!/bin/bash

# Partitioning logic
partition_disk() {
  local disk="$1"
  local disk_size_gb
  disk_size_gb=$(blockdev --getsize64 "$disk")
  disk_size_gb=$(( disk_size_gb / 1024 / 1024 / 1024 ))

  print_message "Partitioning disk: $disk_size_gb GB"
  
  boot_size=+512M
  root_size="+30G"
  home_size=""

  if (( disk_size_gb < 50 )); then
    boot_size="+512M"
    root_size="+10G"
    home_size="$(( disk_size_gb - 10 ))"
  elif (( disk_size_gb >= 50 && disk_size_gb < 250 )); then
    boot_size="+1G"
    root_size="+20G"
    home_size="$(( disk_size_gb - 21 ))"
  else
    boot_size="+1G"
    root_size="+30G"
    home_size="$(( disk_size_gb - 31 ))"
  fi

  print_message "Allocating partitions: Boot: $boot_size, Root: $root_size, Home: $home_size"

  wipefs -a "$disk"

  table_type="o"  # Default to MBR for BIOS
  if [ -d /sys/firmware/efi ]; then
    table_type="g"  # GPT for UEFI
  fi

  {
    echo "$table_type"
    echo n; echo 1; echo; echo "$boot_size"
    echo n; echo 2; echo; echo "$root_size"
    echo n; echo 3; echo; echo "$home_size"
    echo w
  } | fdisk "$disk"
}
