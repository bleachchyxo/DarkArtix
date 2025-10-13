#!/bin/bash
set -euo pipefail

# Root check
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root."
  exit 1
fi

ask() {
  local prompt="$1"
  local default="$2"
  read -rp "$prompt [$default]: " input
  echo "${input:-$default}"
}

confirm() {
  local prompt="$1"
  local default="${2:-no}"
  local yn_format
  [[ "${default,,}" =~ ^(yes|y)$ ]] && yn_format="[Y/n]" || yn_format="[y/N]"
  read -rp "$prompt $yn_format: " answer
  answer="${answer:-$default}"
  [[ "${answer,,}" =~ ^(yes|y)$ ]] || { echo "Aborted."; exit 1; }
}

# Detect firmware
firmware="BIOS"
if [ -d /sys/firmware/efi ]; then
  firmware="UEFI"
fi
echo "Firmware detected: $firmware"

# List disks
echo "Available disks:"
mapfile -t disks < <(lsblk -dno NAME,SIZE,TYPE | awk '$3 == "disk" && $1 !~ /^(loop|ram)/ {print $1, $2}')
for disk_entry in "${disks[@]}"; do
  echo "  $disk_entry"
done

default_disk="${disks[0]%% *}"
disk_name=$(ask "Choose a disk to install" "$default_disk")
disk="/dev/$disk_name"
if [[ ! -b "$disk" ]]; then
  echo "Invalid disk: $disk"
  exit 1
fi
confirm "This will erase all data on $disk. Continue?" "no"

# Compute sizes
disk_size_bytes=$(blockdev --getsize64 "$disk")
disk_size_mb=$(( disk_size_bytes / 1024 / 1024 ))

echo "Disk size (MB): $disk_size_mb"

boot_size_mb=512
buffer_mb=512
usable_mb=$(( disk_size_mb - boot_size_mb - buffer_mb ))

if (( usable_mb <= 0 )); then
  echo "Error: usable space after boot+buffer is <= 0. Abort."
  exit 1
fi

root_size_mb=$(( usable_mb * 60 / 100 ))

boot_size="+${boot_size_mb}M"
root_size="+${root_size_mb}M"

echo "Computed partition sizes:"
echo "  boot_size = $boot_size"
echo "  root_size = $root_size"
echo "  remaining for home = rest of disk"

echo "Wiping disk $disk..."
wipefs -a "$disk"

if [[ "$firmware" == "UEFI" ]]; then
  table_type="g"
else
  table_type="o"
fi

echo "Running fdisk with the following script:"
cat << EOF
$table_type
n
1

$boot_size
n
2

$root_size
n
3


$( [[ "$firmware" == "BIOS" ]] && echo -e "a\n1" )
w
EOF

{
  echo "$table_type"
  echo n; echo 1; echo; echo "$boot_size"
  echo n; echo 2; echo; echo "$root_size"
  echo n; echo 3; echo; echo
  [[ "$firmware" == "BIOS" ]] && echo a && echo 1
  echo w
} | fdisk "$disk" || { echo "fdisk failed"; exit 1; }

echo "fdisk succeeded — partitions:"
lsblk "$disk"

# End here (do not continue full install)
echo "Diagnostic done."
