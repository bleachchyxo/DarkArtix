#!/bin/bash
set -euo pipefail

# --- Root Check ---
[ "$EUID" -ne 0 ] && { echo "Run as root"; exit 1; }

# --- Ask and Confirm ---
ask() {
  local prompt="$1" default="$2" input
  read -rp "$prompt [$default]: " input
  echo "${input:-$default}"
}

confirm() {
  local ans
  ans=$(ask "$1 (yes/no)" "no")
  [[ "${ans,,}" == y || "${ans,,}" == yes ]] || { echo "Aborted."; exit 1; }
}

# --- Detect UEFI or BIOS ---
[ -d /sys/firmware/efi ] && firmware="UEFI" || firmware="BIOS"
echo "Detected firmware: $firmware"

# --- Disk Selection ---
echo "Available disks:"
lsblk -dno NAME,SIZE
disk=$(ask "Install to disk (e.g. sda, nvme0n1)" "$(lsblk -dno NAME | head -n1)")
disk="/dev/$disk"
[ ! -b "$disk" ] && echo "Invalid disk: $disk" && exit 1
confirm "Wipe $disk and install Artix?"

# --- Hostname and User Setup ---
hostname=$(ask "Hostname" "artix")
username=$(ask "Username" "user")

echo "Set root password:"
read -rsp "Password: " rootpass; echo
read -rsp "Confirm: " confirm; echo
[[ "$rootpass" != "$confirm" ]] && { echo "Mismatch."; exit 1; }

echo "Set password for $username:"
read -rsp "Password: " userpass; echo
read -rsp "Confirm: " confirm; echo
[[ "$userpass" != "$confirm" ]] && { echo "Mismatch."; exit 1; }

# --- Timezone Selection ---
select_timezone() {
  while true; do
    echo "Available continents:"
    continents=($(find /usr/share/zoneinfo -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort))
    printf '%s\n' "${continents[@]}"
    continent=$(ask "Continent" "Europe")
    continent=$(printf '%s\n' "${continents[@]}" | grep -iFx "$continent" || true)
    [ -z "$continent" ] && { echo "Invalid. Try again."; continue; }

    echo "Regions in $continent:"
    regions=($(find "/usr/share/zoneinfo/$continent" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null))
    if [ "${#regions[@]}" -gt 0 ]; then
      region=$(ask "Region (e.g. Israel, Germany)" "${regions[0]}")
      region=$(printf '%s\n' "${regions[@]}" | grep -iFx "$region" || true)
      [ -z "$region" ] && { echo "Invalid. Try again."; continue; }

      cities=($(find "/usr/share/zoneinfo/$continent/$region" -type f -exec basename {} \;))
      city=$(ask "City" "${cities[0]}")
      city=$(printf '%s\n' "${cities[@]}" | grep -iFx "$city" || true)
      [ -z "$city" ] && { echo "Invalid. Try again."; continue; }

      timezone="$continent/$region/$city"
    else
      cities=($(find "/usr/share/zoneinfo/$continent" -type f -exec basename {} \;))
      city=$(ask "City" "${cities[0]}")
      city=$(printf '%s\n' "${cities[@]}" | grep -iFx "$city" || true)
      [ -z "$city" ] && { echo "Invalid. Try again."; continue; }

      timezone="$continent/$city"
    fi

    [ -f "/usr/share/zoneinfo/$timezone" ] && break || echo "Timezone not found. Try again."
  done
  echo "Selected timezone: $timezone"
}
select_timezone

# --- Partitioning ---
echo "Partitioning $disk..."
wipefs -a "$disk"

{
  echo g
  echo n; echo 1; echo; echo +1G
  echo n; echo 2; echo; echo +30G
  echo n; echo 3; echo; echo
  echo w
} | fdisk "$disk"

suffix=""
[[ "$disk" =~ nvme ]] && suffix="p"
boot="${disk}${suffix}1"
root="${disk}${suffix}2"
home="${disk}${suffix}3"

# --- Format Partitions ---
echo "Formatting..."
if [ "$firmware" == "UEFI" ]; then
  mkfs.fat -F32 "$boot"
else
  mkfs.ext4 "$boot"
fi
mkfs.ext4 "$root"
mkfs.ext4 "$home"

# --- Mount Partitions ---
mount "$root" /mnt
mkdir -p /mnt/boot /mnt/home
mount "$boot" /mnt/boot
mount "$home" /mnt/home

# --- Install Base System ---
basestrap /mnt base base-devel runit elogind-runit linux linux-firmware grub efibootmgr neovim

# --- Generate FSTAB ---
fstabgen -U /mnt > /mnt/etc/fstab

# --- Configure System in Chroot ---
artix-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc

sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "$hostname" > /etc/hostname
echo "127.0.1.1 $hostname.localdomain $hostname" >> /etc/hosts

echo "root:$rootpass" | chpasswd
useradd -m -G wheel $username
echo "$username:$userpass" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

pacman -Sy --noconfirm networkmanager networkmanager-runit
ln -s /etc/runit/sv/NetworkManager /etc/runit/runsvdir/default

if [ "$firmware" = "UEFI" ]; then
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
  grub-install --target=i386-pc "$disk"
fi
grub-mkconfig -o /boot/grub/grub.cfg
EOF

echo "Installation complete. Reboot to enjoy your new Artix system."
