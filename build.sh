#!/bin/bash
set -euo pipefail

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root."
  exit 1
fi

firmware="BIOS"
[ -d /sys/firmware/efi ] && firmware="UEFI"

# Function to print colored messages
message() {
  local color="$1"
  local msg="$2"
  case "$color" in
    green)  echo -e "\033[32m[+]\033[0m $msg" ;;
    yellow) echo -e "\033[33m[+]\033[0m $msg" ;;
    blue)   echo -e "\033[34m[+]\033[0m $msg" ;;
    *)      echo "[+] $msg" ;;
  esac
}

# Prompt with default value
default_prompt() {
  local prompt="$1"
  local default="$2"
  read -rp "$prompt [$default]: " input
  echo "${input:-$default}"
}

# Yes/No confirmation prompt with default answer
confirmation() {
  local prompt="$1"
  local default="${2:-no}"
  local yn_format
  [[ "${default,,}" =~ ^(yes|y)$ ]] && yn_format="[Y/n]" || yn_format="[y/N]"
  read -rp "$prompt $yn_format: " answer
  answer="${answer:-$default}"
  [[ "${answer,,}" =~ ^(yes|y)$ ]] || { echo "Aborted."; exit 1; }
}

echo "DarkArtix Installer v0.1"
echo "Firmware: $firmware"

# List available disks for installation
message blue "Choosing a disk"
echo "Available disks:"
mapfile -t available_disks < <(lsblk -dno NAME,SIZE,TYPE | awk '$3 == "disk" && $1 !~ /loop/ && $1 !~ /ram/ {print $1, $2}')

if [[ ${#available_disks[@]} -eq 0 ]]; then
  echo "No disks detected."
  exit 1
fi

# Show disks with sizes
for disk_entry in "${available_disks[@]}"; do
  echo "  $disk_entry"
done

default_disk="${available_disks[0]%% *}"
disk_choice=$(default_prompt "Choose a disk to install" "$default_disk")
disk="/dev/$disk_choice"

# Validate disk choice
if [[ -z "${disk_choice:-}" || ! -b "$disk" ]]; then
  echo "Invalid or missing disk selection."
  exit 1
fi

confirmation "This will erase all data on $disk. Continue?" "no"

disk_name=$(basename "$disk")
total_gb=$(( $(< /sys/block/$disk_name/size) * $(< /sys/block/$disk_name/queue/hw_sector_size) / 1024 / 1024 / 1024 ))

case $total_gb in
  [0-9]) boot_size=0.5 root_size=4 ;;
  1[0-9]) boot_size=0.5 root_size=6 ;;
  2[0-9]|3[0-9]) boot_size=1 root_size=8 ;;
  [4-9][0-9]) boot_size=1 root_size=20 ;;
  1[0-9][0-9]|*) boot_size=1 root_size=30 ;;
esac

for partition in $(lsblk -ln -o NAME "$disk_path" | tail -n +2); do
    mount_point=$(lsblk -ln -o MOUNTPOINT "/dev/$partition")
    [ -n "$mount_point" ] && umount "/dev/$partition"
done

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

if [ "$firmware" = "UEFI" ]; then
  mkfs.fat -F32 "${disk}1"
else
  mkfs.ext4 -F "${disk}1"
fi
mkfs.ext4 -F "${disk}2"
mkfs.ext4 -F "${disk}3"

fdisk -l "$disk" | grep "$disk"
