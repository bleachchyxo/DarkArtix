#!/bin/bash
set -euo pipefail

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root."
  exit 1
fi

# Prompt with default
ask() {
  read -rp "$1 [$2]: " input
  echo "${input:-$2}"
}

# Select timezone (Continent/City)
choose_timezone() {
  echo "Available continents:"
  find /usr/share/zoneinfo -maxdepth 1 -mindepth 1 -type d | xargs -n1 basename | sort
  continent=$(ask "Continent" "America")
  city_list=$(find /usr/share/zoneinfo/$continent -type f | sed "s|/usr/share/zoneinfo/$continent/||" | sort)
  echo "Available cities in $continent:"
  echo "$city_list"
  city=$(ask "City" "New_York")
  timezone="$continent/$city"
}

# Detect BIOS or UEFI
firmware="BIOS"
[ -d /sys/firmware/efi ] && firmware="UEFI"
echo "Detected firmware: $firmware"

# Choose disk
echo "Available disks:"
lsblk -dn -o NAME,SIZE
disk=$(ask "Disk to install to (e.g. sda)" "$(lsblk -dn -o NAME | head -n1)")
disk="/dev/$disk"

if [ ! -b "$disk" ]; then
  echo "Invalid disk: $disk"
  exit 1
fi

# Confirm wipe
echo "!!! WARNING: This will ERASE ALL DATA on $disk !!!"
confirm=$(ask "Type YES to continue" "no")
[[ "$confirm" != "YES" ]] && exit 1

# Hostname and user
hostname=$(ask "Hostname" "artix")
username=$(ask "Username" "user")

# Passwords
echo "Set root password:"
read -rsp "Password: " rootpass; echo
read -rsp "Confirm: " rootpass2; echo
[ "$rootpass" != "$rootpass2" ] && echo "Mismatch!" && exit 1

echo "Set password for $username:"
read -rsp "Password: " userpass; echo
read -rsp "Confirm: " userpass2; echo
[ "$userpass" != "$userpass2" ] && echo "Mismatch!" && exit 1

# Partition disk
echo "Partitioning $disk..."
wipefs -a "$disk"
{
  echo g
  if [ "$firmware" = "UEFI" ]; then
    echo n; echo 1; echo; echo +512M
    echo t; echo 1; echo 1
    echo n; echo 2; echo; echo
  else
    echo n; echo 1; echo; echo +1G
    echo n; echo 2; echo; echo
  fi
  echo w
} | fdisk "$disk"

# Set partition paths
if [[ "$disk" == *"nvme"* ]]; then
  boot="${disk}p1"
  root="${disk}p2"
else
  boot="${disk}1"
  root="${disk}2"
fi

# Format partitions
[ "$firmware" = "UEFI" ] && mkfs.fat -F32 "$boot" || mkfs.ext4 "$boot"
mkfs.ext4 "$root"

# Mount
mount "$root" /mnt
mkdir -p /mnt/boot/efi
mount "$boot" /mnt/boot/efi

# Install base system
basestrap /mnt base base-devel runit elogind-runit linux linux-firmware grub efibootmgr neovim

# Generate fstab
fstabgen -U /mnt > /mnt/etc/fstab

# Timezone
choose_timezone

# Chroot configuration
artix-chroot /mnt /bin/bash -e <<EOF
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc

sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "$hostname" > /etc/hostname
echo "127.0.0.1 localhost" > /etc/hosts
echo "::1       localhost" >> /etc/hosts
echo "127.0.1.1 $hostname.localdomain $hostname" >> /etc/hosts

echo "root:$rootpass" | chpasswd
useradd -m -G wheel $username
echo "$username:$userpass" | chpasswd

sed -i 's/^# %wheel/%wheel/' /etc/sudoers

ln -s /etc/runit/sv/sshd /etc/runit/runsvdir/default 2>/dev/null || true

# Install GRUB
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
EOF

echo "✔ Installation complete. Reboot when ready."
