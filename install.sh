#!/bin/bash
set -euo pipefail

# === Root check ===
if [ "$EUID" -ne 0 ]; then
  echo "Run this script as root."
  exit 1
fi

# === Helper functions ===
ask() {
  read -rp "$1 [$2]: " input
  echo "${input:-$2}"
}

confirm() {
  response=$(ask "$1 (yes/no)" "no")
  case "${response,,}" in
    y|yes) return 0 ;;
    *) echo "Aborted."; exit 1 ;;
  esac
}

choose_timezone() {
  echo "Available continents:"
  continents=$(find /usr/share/zoneinfo -mindepth 1 -maxdepth 1 -type d | xargs -n1 basename | sort)
  echo "$continents"

  continent=$(ask "Continent" "America")
  continent=$(echo "$continents" | grep -iFx "$continent" || true)
  [ -z "$continent" ] && echo "Invalid continent." && exit 1

  echo "Available locations in $continent:"
  cities=$(find "/usr/share/zoneinfo/$continent" -type f | sed "s|/usr/share/zoneinfo/$continent/||" | sort)
  default_city=$(echo "$cities" | shuf -n1)

  city=$(ask "City" "$default_city")
  city=$(echo "$cities" | grep -iFx "$city" || true)
  [ -z "$city" ] && echo "Invalid city." && exit 1

  timezone="$continent/$city"
  echo "Timezone set to: $timezone"
}

# === Detect firmware ===
firmware="BIOS"
[ -d /sys/firmware/efi ] && firmware="UEFI"
echo "Firmware: $firmware"

# === Disk selection ===
echo "Available disks:"
lsblk -dn -o NAME,SIZE
disk=$(ask "Install to disk (e.g. sda, nvme0n1)" "$(lsblk -dn -o NAME | head -n1)")
disk="/dev/$disk"
[ ! -b "$disk" ] && echo "Invalid disk: $disk" && exit 1

confirm "Wipe $disk and install Artix?"

# === Hostname, user, passwords ===
hostname=$(ask "Hostname" "artix")
username=$(ask "Username" "user")

echo "Set root password:"
read -rsp "Password: " rootpass; echo
read -rsp "Confirm: " rootpass2; echo
[ "$rootpass" != "$rootpass2" ] && echo "Mismatch." && exit 1

echo "Set user password:"
read -rsp "Password: " userpass; echo
read -rsp "Confirm: " userpass2; echo
[ "$userpass" != "$userpass2" ] && echo "Mismatch." && exit 1

# === Get disk size and calculate layout ===
disk_size_mib=$(lsblk -b -dn -o SIZE "$disk")
disk_size_mib=$((disk_size_mib / 1024 / 1024))

if [ "$disk_size_mib" -ge 35840 ]; then
  boot_end="+1G"
  root_end="+30G"
else
  boot_end="+1G"
  usable=$((disk_size_mib - 1024))
  root_end="+$((usable * 70 / 100))M"
fi

# === Partition disk ===
echo "Partitioning $disk..."
wipefs -a "$disk"

{
  echo g
  echo n; echo 1; echo; echo "$boot_end"
  echo n; echo 2; echo; echo "$root_end"
  echo n; echo 3; echo; echo
  echo w
} | fdisk "$disk"

# === Set partition names ===
if [[ "$disk" == *"nvme"* ]]; then
  boot="${disk}p1"
  root="${disk}p2"
  home="${disk}p3"
else
  boot="${disk}1"
  root="${disk}2"
  home="${disk}3"
fi

# === Format partitions ===
echo "Formatting partitions..."
if [ "$firmware" = "UEFI" ]; then
  mkfs.fat -F32 "$boot"
else
  mkfs.ext4 "$boot"
fi
mkfs.ext4 "$root"
mkfs.ext4 "$home"

# === Mount filesystems ===
mount "$root" /mnt
mkdir -p /mnt/boot /mnt/home
mount "$boot" /mnt/boot
mount "$home" /mnt/home

# === Install base system ===
basestrap /mnt base base-devel runit elogind-runit linux linux-firmware grub efibootmgr neovim

# === Generate fstab ===
fstabgen -U /mnt > /mnt/etc/fstab

# === Select timezone ===
choose_timezone

# === Configure system ===
artix-chroot /mnt /bin/bash -e <<EOF
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc

sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "$hostname" > /etc/hostname

# Append 127.0.1.1 only
grep -q "$hostname" /etc/hosts || echo "127.0.1.1   $hostname.localdomain $hostname" >> /etc/hosts

echo "root:$rootpass" | chpasswd
useradd -m -G wheel $username
echo "$username:$userpass" | chpasswd

sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# NetworkManager
pacman -S --noconfirm networkmanager networkmanager-runit
ln -s /etc/runit/sv/NetworkManager /etc/runit/runsvdir/default

# GRUB
if [ "$firmware" = "UEFI" ]; then
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
  grub-install --target=i386-pc "$disk"
fi

grub-mkconfig -o /boot/grub/grub.cfg
EOF

echo "Installation complete. You may reboot."
