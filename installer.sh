#!/bin/bash
set -euo pipefail

# Root check
if [[ $EUID -ne 0 ]]; then
  echo -e "\033[1;33m[ + ]\033[0m Please run as root."
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
  read -rp "$prompt [y/N]: " answer
  answer="${answer:-$default}"
  [[ "${answer,,}" =~ ^(yes|y)$ ]] || { echo "Aborted."; exit 1; }
}

msg() {
  local color="$1"
  local message="$2"
  local color_code
  case "$color" in
    "yellow") color_code='\033[1;33m' ;;  # Yellow for warnings
    "blue") color_code='\033[1;34m' ;;    # Blue for standard actions
    "green") color_code='\033[1;32m' ;;   # Green for success
    *) color_code='\033[0m' ;;            # Default
  esac
  echo -e -n "["
  echo -e -n "\033[1;32m+"  # Color the [+] part green
  echo -e -n "\033[0m] "  # Reset back to default for the rest of the message
  echo -e "$message"  # Print the rest of the message
}

# Detect firmware
firmware="BIOS"
if [ -d /sys/firmware/efi ]; then
  firmware="UEFI"
fi
echo "Firmware: $firmware"

# Disk selection
msg "yellow" "WARNING: This will erase your entire disk."
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
confirm "Are you sure you want to erase all data on $disk?" "no"

# Hostname and username
hostname=$(ask "Hostname" "artix")
username=$(ask "Username" "user")

# Timezone selection
msg "blue" "Choosing your timezone:"
echo "Available continents:"
mapfile -t continents < <(find /usr/share/zoneinfo -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)
continent_count=${#continents[@]}
columns=4  # Number of columns per row
for ((i=0; i<continent_count; i+=columns)); do
  echo "${continents[@]:i:columns}" | column -t
done
continent_input=$(ask "Continent" "America")
continent=$(echo "$continent_input" | awk '{print tolower($0)}')
continent_matched=""
for c in "${continents[@]}"; do
  if [[ "${c,,}" == "$continent" ]]; then
    continent_matched="$c"
    break
  fi
done
timezone="$continent_matched/$(ask "City" "New_York")"  # Example for default city selection

# Partitioning
msg "blue" "Creating partitions on $disk..."
wipefs -a "$disk"
if [[ "$firmware" == "UEFI" ]]; then
  table_type="g"
else
  table_type="o"
fi
{
  echo "$table_type"
  echo n; echo 1; echo; echo +512M
  echo n; echo 2; echo; echo +30G
  echo n; echo 3; echo; echo
  [[ "$firmware" == "BIOS" ]] && echo a && echo 1
  echo w
} | fdisk "$disk"

# Partition device names (handling NVMe and MMC disks)
part_prefix=""
[[ "$disk" =~ nvme || "$disk" =~ mmcblk ]] && part_prefix="p"

boot_partition="${disk}${part_prefix}1"
root_partition="${disk}${part_prefix}2"
home_partition="${disk}${part_prefix}3"

# Waiting for partitions to appear with a timeout mechanism
timeout=30  # Timeout in seconds
counter=0

# Check if partitions exist
for p in "$boot_partition" "$root_partition" "$home_partition"; do
  while [ ! -b "$p" ]; do
    sleep 0.5
    counter=$((counter + 1))
    if [[ $counter -ge $timeout ]]; then
      msg "yellow" "Timeout reached. Partition $p is not available."
      break
    fi
  done
done

# Format partitions
msg "blue" "Formatting partitions..."
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
msg "blue" "Setting root and user passwords:"
while true; do
  read -s -p "Root password: " rootpass1; echo
  read -s -p "Confirm root password: " rootpass2; echo
  [[ "$rootpass1" == "$rootpass2" && -n "$rootpass1" ]] && break || echo "Passwords do not match or are empty. Try again."
done

# Prompt for user password
while true; do
  read -s -p "User password for '$username': " userpass1; echo
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

# Final success message
msg "green" "Installation successfully completed! Please reboot and remove the installation media."
