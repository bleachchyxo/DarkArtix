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

# Detect firmware
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

# Disk selection
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
timezone=$(ask "Timezone" "America/New_York")

# Partition sizing (flexible partitioning)
disk_size_bytes=$(blockdev --getsize64 "$disk")
disk_size_gb=$(( disk_size_bytes / 1024 / 1024 / 1024 ))

# Set partition sizes based on disk size
boot_size="1G"
if (( disk_size_gb < 40 )); then
  root_size=$(( disk_size_gb * 30 / 100 ))"G"  # 30% of disk size for small disks
else
  root_size="30G"  # 30GB for larger disks
fi

# Remaining space for /home
remaining_size=$(( disk_size_gb - 1 - ${root_size%G} ))

echo "Disk Size: $disk_size_gb GB"
echo "Partitioning will be as follows:"
echo "  /boot = $boot_size"
echo "  / = $root_size"
echo "  /home = ${remaining_size}G"

# Wipe existing partition table
wipefs -a "$disk"

# Partitioning with fdisk (creating a GPT partition table)
{
  echo g  # GPT partition table
  echo n  # /boot partition
  echo    # Partition number 1
  echo    # Default start
  echo +$boot_size  # Partition size
  echo n  # / partition
  echo    # Partition number 2
  echo    # Default start
  echo +$root_size  # Partition size
  echo n  # /home partition
  echo    # Partition number 3
  echo    # Default start (use the remaining space)
  echo w  # Write changes
} | fdisk "$disk"

# Wait for partitions to be available
sleep 2

# Format partitions
mkfs.ext4 "${disk}1"  # /boot
mkfs.ext4 "${disk}2"  # /
mkfs.ext4 "${disk}3"  # /home

# Mount partitions
mount "${disk}2" /mnt  # mount /
mkdir -p /mnt/boot /mnt/home
mount "${disk}1" /mnt/boot  # mount /boot
mount "${disk}3" /mnt/home  # mount /home

# Bind mount system directories
for dir in dev proc sys run; do
  mkdir -p "/mnt/$dir"
  mount --bind "/$dir" "/mnt/$dir"
done

# Install base system (customizable packages)
base_packages=(base base-devel runit elogind-runit linux linux-firmware neovim networkmanager networkmanager-runit grub)
[[ "$firmware" == "UEFI" ]] && base_packages+=(efibootmgr)

# Installing base system
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

echo
echo "Installation complete. Please reboot and remove the installation media."
