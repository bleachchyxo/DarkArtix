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

# Partition sizing logic
disk_size_bytes=$(blockdev --getsize64 "$disk")
disk_size_gb=$(( disk_size_bytes / 1024 / 1024 / 1024 ))

# Set partition sizes
boot_size="1G"
root_size="30G"
home_size=$(( disk_size_gb - 31 ))"G"  # Remaining space for /home (subtract 1G for /boot and 30G for /)

if (( disk_size_gb < 40 )); then
  root_size="+10G"
  home_size="+5G"
fi

echo "Wiping and partitioning $disk..."
wipefs -a "$disk"

# Create partition table (GPT for UEFI, MBR for BIOS)
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

# Partition device names (handles NVMe/other cases)
part_prefix=""
[[ "$disk" =~ nvme || "$disk" =~ mmcblk ]] && part_prefix="p"

boot_partition="${disk}${part_prefix}1"
root_partition="${disk}${part_prefix}2"
home_partition="${disk}${part_prefix}3"

echo "Waiting for partitions to appear..."
for p in "$boot_partition" "$root_partition" "$home_partition"; do
  while [ ! -b "$p" ]; do sleep 0.5; done
done

# Format partitions
if [[ "$firmware" == "UEFI" ]]; then
  mkfs.fat -F32 "$boot_partition"
else
  mkfs.ext4 "$boot_partition"
fi
mkfs.ext4 "$root_partition"
mkfs.ext4 "$home_partition"

# Mount partitions
mount "$root_partition" /mnt
mkdir -p /mnt/boot /mnt/home
mount "$boot_partition" /mnt/boot
mount "$home_partition" /mnt/home

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

# Prompt for root password
echo "Set root password:"
while true; do
  read -s -p "Root password: " rootpass1; echo
  read -s -p "Confirm root password: " rootpass2; echo
  [[ "$rootpass1" == "$rootpass2" && -n "$rootpass1" ]] && break || echo "Passwords do not match or are empty. Try again."
done

# Prompt for user password
echo "Set password for user '$username':"
while true; do
  read -s -p "User password: " userpass1; echo
  read -s -p "Confirm user password: " userpass2; echo
  [[ "$userpass1" == "$userpass2" && -n "$userpass1" ]] && break || echo "Passwords do not match or are empty. Try again."
done

# Configure system in chroot
artix-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc

sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "$hostname" > /etc/hostname
echo -e "127.0.1.1 \t$hostname.localdomain $hostname" >> /etc/hosts

useradd -m -G wheel "$username"
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

ln -s /etc/runit/sv/NetworkManager /etc/runit/runsvdir/default 2>/dev/null || true

if [[ "$firmware" == "UEFI" ]]; then
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
  grub-install --target=i386-pc "$disk"
fi

grub-mkconfig -o /boot/grub/grub.cfg

echo "root:$rootpass1" | chpasswd
echo "$username:$userpass1" | chpasswd
EOF

# Cleanup sensitive variables
unset rootpass1 rootpass2 userpass1 userpass2

# Unmount system dirs
for dir in dev proc sys run; do
  umount -l "/mnt/$dir"
done

# Unmount partitions
umount -R /mnt

echo
echo "Installation complete. Please reboot and remove the installation media."
