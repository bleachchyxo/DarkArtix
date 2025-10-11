#!/bin/bash
set -euo pipefail

# --- Root check ---
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root."
  exit 1
fi

# --- Prompt helpers ---
ask() {
  local prompt="$1"
  local default="$2"
  read -rp "$prompt [$default]: " input
  echo "${input:-$default}"
}

confirm() {
  local answer
  answer=$(ask "$1 (yes/no)" "no")
  [[ "${answer,,}" == "yes" || "${answer,,}" == "y" ]] || { echo "Aborted."; exit 1; }
}

# --- Detect firmware ---
firmware="BIOS"
if [ -d /sys/firmware/efi ]; then
  firmware="UEFI"
fi
echo "Firmware detected: $firmware"

# --- Disk selection ---
echo "Available disks:"
lsblk -dno NAME,SIZE,TYPE | grep -w disk
disk_name=$(ask "Disk to install to (e.g. sda, vda, nvme0n1)" "$(lsblk -dno NAME | head -n1)")
disk="/dev/$disk_name"

if [[ ! -b "$disk" ]]; then
  echo "Invalid disk: $disk"
  exit 1
fi

confirm "This will erase all data on $disk. Continue?"

# --- Hostname and user ---
hostname=$(ask "Hostname" "artix")
username=$(ask "Username" "user")

echo "Set root password:"
read -rsp "Password: " root_password; echo
read -rsp "Confirm: " confirm_password; echo
[[ "$root_password" != "$confirm_password" ]] && { echo "Passwords do not match."; exit 1; }

echo "Set password for $username:"
read -rsp "Password: " user_password; echo
read -rsp "Confirm: " confirm_password; echo
[[ "$user_password" != "$confirm_password" ]] && { echo "Passwords do not match."; exit 1; }

# --- Timezone ---
echo "Available continents:"
find /usr/share/zoneinfo -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort
continent=$(ask "Continent" "Europe")
echo "Available cities in $continent:"
find "/usr/share/zoneinfo/$continent" -type f -exec basename {} \; | sort
city=$(ask "City" "Berlin")
timezone="$continent/$city"

# --- Partitioning ---
echo "Wiping and partitioning $disk..."
wipefs -a "$disk"

{
  echo g
  echo n; echo 1; echo; echo +512M
  echo t; echo 1
  echo n; echo 2; echo; echo
  echo w
} | fdisk "$disk"

part_prefix=""
[[ "$disk" =~ nvme || "$disk" =~ mmcblk ]] && part_prefix="p"

boot_partition="${disk}${part_prefix}1"
root_partition="${disk}${part_prefix}2"

echo "Waiting for partitions to be available..."
for part in "$boot_partition" "$root_partition"; do
  while [ ! -b "$part" ]; do sleep 0.5; done
done

# --- Formatting ---
if [[ "$firmware" == "UEFI" ]]; then
  mkfs.fat -F32 "$boot_partition"
else
  mkfs.ext4 "$boot_partition"
fi
mkfs.ext4 "$root_partition"

# --- Mounting ---
mount "$root_partition" /mnt
mkdir -p /mnt/boot
mount "$boot_partition" /mnt/boot

# --- Base system installation ---
basestrap /mnt base base-devel runit elogind-runit linux linux-firmware grub efibootmgr neovim

fstabgen -U /mnt > /mnt/etc/fstab

# --- System configuration ---
artix-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc

sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "127.0.1.1 $hostname.localdomain $hostname" >> /etc/hosts

echo "root:$root_password" | chpasswd
useradd -m -G wheel $username
echo "$username:$user_password" | chpasswd

sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

ln -s /etc/runit/sv/sshd /etc/runit/runsvdir/default 2>/dev/null || true

if [[ "$firmware" == "UEFI" ]]; then
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
  grub-install --target=i386-pc "$disk"
fi

grub-mkconfig -o /boot/grub/grub.cfg
EOF

echo "Installation complete. Please reboot."

