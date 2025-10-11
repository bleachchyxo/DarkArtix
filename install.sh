#!/bin/bash
set -euo pipefail

# === Root check ===
if [ "$EUID" -ne 0 ]; then
  echo "Run this script as root."
  exit 1
fi

# === Prompt with default ===
ask() {
  read -rp "$1 [$2]: " input
  echo "${input:-$2}"
}

# === Confirm prompt (case-insensitive) ===
confirm() {
  response=$(ask "$1 (yes/no)" "no")
  case "${response,,}" in
    y|yes) return 0 ;;
    *) echo "Aborted."; exit 1 ;;
  esac
}

# === Timezone selection ===
choose_timezone() {
  echo "Available continents:"
  continents=$(find /usr/share/zoneinfo -mindepth 1 -maxdepth 1 -type d | xargs -n1 basename | sort)
  echo "$continents"

  input_continent=$(ask "Continent" "America")
  continent=$(echo "$continents" | grep -iFx "$input_continent" || true)
  [ -z "$continent" ] && echo "Invalid continent: $input_continent" && exit 1

  city_list=$(find "/usr/share/zoneinfo/$continent" -type f | sed "s|/usr/share/zoneinfo/$continent/||" | sort)
  default_city=$(echo "$city_list" | shuf -n1)

  echo "Available cities in $continent:"
  echo "$city_list"

  input_city=$(ask "City" "$default_city")
  city=$(echo "$city_list" | grep -iFx "$input_city" || true)
  [ -z "$city" ] && echo "Invalid city: $input_city" && exit 1

  timezone="$continent/$city"
  echo "Timezone selected: $timezone"
}

# === Detect firmware ===
firmware="BIOS"
[ -d /sys/firmware/efi ] && firmware="UEFI"
echo "Detected firmware: $firmware"

# === Disk selection ===
echo "Available disks:"
lsblk -dn -o NAME,SIZE
disk=$(ask "Install to disk (e.g. sda, nvme0n1)" "$(lsblk -dn -o NAME | head -n1)")
disk="/dev/$disk"
[ ! -b "$disk" ] && echo "Invalid disk: $disk" && exit 1

confirm "Are you sure you want to wipe $disk?"

# === Hostname, username, passwords ===
hostname=$(ask "Hostname" "artix")
username=$(ask "Username" "user")

echo "Set root password:"
read -rsp "Password: " rootpass; echo
read -rsp "Confirm: " rootpass2; echo
[ "$rootpass" != "$rootpass2" ] && echo "Passwords do not match." && exit 1

echo "Set password for $username:"
read -rsp "Password: " userpass; echo
read -rsp "Confirm: " userpass2; echo
[ "$userpass" != "$userpass2" ] && echo "Passwords do not match." && exit 1

# === Partitioning ===
echo "Partitioning $disk..."
wipefs -a "$disk"

{
  echo g
  if [ "$firmware" = "UEFI" ]; then
    echo n; echo 1; echo; echo +512M
    echo t; echo 1; echo ef
    echo n; echo 2; echo; echo
  else
    echo n; echo 1; echo; echo +1G
    echo n; echo 2; echo; echo
  fi
  echo w
} | fdisk "$disk"

# === Partition names ===
if [[ "$disk" == *"nvme"* ]]; then
  boot="${disk}p1"
  root="${disk}p2"
else
  boot="${disk}1"
  root="${disk}2"
fi

# === Format partitions ===
echo "Formatting partitions..."
if [ "$firmware" = "UEFI" ]; then
  mkfs.fat -F32 "$boot"
else
  mkfs.ext4 "$boot"
fi
mkfs.ext4 "$root"

# === Mounting ===
mount "$root" /mnt
mkdir -p /mnt/boot/efi
mount "$boot" /mnt/boot/efi

# === Base system install ===
basestrap /mnt base base-devel runit elogind-runit linux linux-firmware grub efibootmgr neovim

# === fstab ===
fstabgen -U /mnt > /mnt/etc/fstab

# === Timezone ===
choose_timezone

# === System configuration ===
artix-chroot /mnt /bin/bash -e <<EOF
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc

sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "$hostname" > /etc/hostname

# Avoid duplicating localhost entries
echo "127.0.1.1   $hostname.localdomain $hostname" >> /etc/hosts

echo "root:$rootpass" | chpasswd
useradd -m -G wheel $username
echo "$username:$userpass" | chpasswd

sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Enable NetworkManager
pacman -S --noconfirm networkmanager networkmanager-runit
ln -s /etc/runit/sv/NetworkManager /etc/runit/runsvdir/default

# GRUB install
if [ "$firmware" = "UEFI" ]; then
  grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
else
  grub-install --target=i386-pc "$disk"
fi

grub-mkconfig -o /boot/grub/grub.cfg
EOF

echo "✔ Installation complete. Reboot when ready."
