#!/bin/bash
set -euo pipefail

# Root check
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root."
  exit 1
fi

# Prompt helpers
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

# Detect firmware type
firmware="BIOS"
if [ -d /sys/firmware/efi ]; then
  firmware="UEFI"
fi
echo "Firmware detected: $firmware"

# List available disks
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

# Hostname and username
hostname=$(ask "Hostname" "artix")
username=$(ask "Username" "user")

# Timezone selection
# (Same as your script, omitted for brevity)

# Partition sizing logic (adjust for any disk size)
disk_size_bytes=$(blockdev --getsize64 "$disk")
disk_size_gb=$(( disk_size_bytes / 1024 / 1024 / 1024 ))

# Default partition sizes (1G for /boot, 30G for /, the rest for /home)
boot_size="1G"
root_size="30G"
home_size=$(( disk_size_gb - 31 ))"G"  # Remaining space for /home

# Ensure partitions fit for smaller disks like VM disks
if (( disk_size_gb < 40 )); then
  root_size="10G"
  home_size="5G"
fi

echo "Partitioning $disk..."
wipefs -a "$disk"

# Partition creation
{
  if [[ "$firmware" == "UEFI" ]]; then
    echo g  # GPT for UEFI
  else
    echo o  # MBR for BIOS
  fi

  # /boot partition (1G)
  echo n
  echo p
  echo 1
  echo
  echo "$boot_size"

  # / partition (30G or less if needed)
  echo n
  echo p
  echo 2
  echo
  echo "$root_size"

  # /home partition (remaining space)
  echo n
  echo p
  echo 3
  echo
  echo "$home_size"

  # Mark bootable if BIOS
  if [[ "$firmware" == "BIOS" ]]; then
    echo a
    echo 1
  fi

  echo w
} | fdisk "$disk"

# Wait for partitions to appear
echo "Waiting for partitions to appear..."
for part in "$disk"1 "$disk"2 "$disk"3; do
  while [ ! -b "$part" ]; do sleep 0.5; done
done

# Format partitions
if [[ "$firmware" == "UEFI" ]]; then
  mkfs.fat -F32 "$disk"1
else
  mkfs.ext4 "$disk"1
fi
mkfs.ext4 "$disk"2
mkfs.ext4 "$disk"3

# Mount partitions
mount "$disk"2 /mnt
mkdir -p /mnt/boot /mnt/home
mount "$disk"1 /mnt/boot
mount "$disk"3 /mnt/home

# Bind mount system dirs
for dir in dev proc sys run; do
  mkdir -p "/mnt/$dir"
  mount --bind "/$dir" "/mnt/$dir"
done

# Install base system
base_packages=(base base-devel runit elogind-runit linux linux-firmware neovim networkmanager networkmanager-runit grub)
[[ "$firmware" == "UEFI" ]] && base_packages+=(efibootmgr)

basestrap /mnt "${base_packages[@]}"
fstabgen -U /mnt > /mnt/etc/fstab

# Prompt for root and user passwords
# (Same as your original script)

# Configure system in chroot
# (Same as your original script)

# Cleanup sensitive variables
# (Same as your original script)

# Unmount partitions
umount -R /mnt

echo "Installation complete. Please reboot and remove the installation media."

