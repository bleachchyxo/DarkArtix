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

# Display colored [+] message
print_message() {
  echo -e "\033[32m[+]\033[0m $1"
}

# Detect firmware
firmware="BIOS"
if [ -d /sys/firmware/efi ]; then
  firmware="UEFI"
fi
echo "Firmware detected: $firmware"

# List available disks
print_message "Available disks:"
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
print_message "Available continents:"
mapfile -t continents < <(find /usr/share/zoneinfo -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)
for c in "${continents[@]}"; do echo "  $c"; done

continent_input=$(ask "Continent" "America")
continent=$(echo "$continent_input" | awk '{print tolower($0)}')
continent_matched=""
for c in "${continents[@]}"; do
  if [[ "${c,,}" == "$continent" ]]; then
    continent_matched="$c"
    break
  fi
done
if [[ -z "$continent_matched" ]]; then
  echo "Invalid continent '$continent_input'. Please try again."
  exit 1
fi

# Pick cities based on continent
print_message "Available cities in $continent_matched:"
mapfile -t cities < <(find "/usr/share/zoneinfo/$continent_matched" -type f -exec basename {} \; | sort)

cols=4
for i in "${!cities[@]}"; do
  if (( i % cols == 0 )); then
    echo
  fi
  printf "%-15s" "${cities[$i]}"
done
echo

city_input=$(ask "City" "${cities[0]}")
city=$(echo "$city_input" | awk '{print tolower($0)}')
city_matched=""
for c in "${cities[@]}"; do
  if [[ "${c,,}" == "$city" ]]; then
    city_matched="$c"
    break
  fi
done
if [[ -z "$city_matched" ]]; then
  echo "Invalid city '$city_input'. Please try again."
  exit 1
fi
timezone="$continent_matched/$city_matched"

print_message "Unmounting any mounted partitions on $disk..."
for part in $(lsblk -lnpo NAME "$disk" | tail -n +2); do
  umount "$part" 2>/dev/null || true
done

print_message "Disabling any swap on $disk..."
swapoff -a 2>/dev/null || true

print_message "Wiping and partitioning $disk..."
wipefs -a "$disk"

# Partition sizes: target 1G /boot, 30G /, rest /home
boot_size_gb=1
target_root_size_gb=30

# Get total disk size
disk_size_bytes=$(blockdev --getsize64 "$disk")
disk_size_gb=$(( disk_size_bytes / 1024 / 1024 / 1024 ))

min_disk_required=$(( boot_size_gb + 5 ))
if (( disk_size_gb < min_disk_required )); then
  echo "Error: Disk size ($disk_size_gb GB) is too small. Minimum required: ${min_disk_required}GB."
  exit 1
fi

# Adjust root size if needed
if (( disk_size_gb < boot_size_gb + target_root_size_gb + 1 )); then
  root_size_gb=$(( disk_size_gb / 2 ))
  home_size_gb=$(( disk_size_gb - boot_size_gb - root_size_gb ))
else
  root_size_gb=$target_root_size_gb
  home_size_gb=$(( disk_size_gb - boot_size_gb - root_size_gb ))
fi

# Convert sizes to sectors
sector_size=$(blockdev --getss "$disk")
total_sectors=$(blockdev --getsz "$disk")

boot_size_sectors=$(( boot_size_gb * 1024 * 1024 * 1024 / sector_size ))
root_size_sectors=$(( root_size_gb * 1024 * 1024 * 1024 / sector_size ))
home_size_sectors=$(( home_size_gb * 1024 * 1024 * 1024 / sector_size ))

# Partition layout
part1_start=2048
part1_end=$(( part1_start + boot_size_sectors - 1 ))

part2_start=$(( part1_end + 1 ))
part2_end=$(( part2_start + root_size_sectors - 1 ))

part3_start=$(( part2_end + 1 ))
part3_end=$(( total_sectors - 1 ))

print_message "Partition layout:"
echo "/boot   : ${boot_size_gb}G (sectors $part1_start - $part1_end)"
echo "/       : ${root_size_gb}G (sectors $part2_start - $part2_end)"
echo "/home   : ${home_size_gb}G (sectors $part3_start - $part3_end)"

# Wipe and partition
print_message "Wiping and partitioning $disk..."
wipefs -a "$disk"

{
  [[ "$firmware" == "UEFI" ]] && echo g || echo o

  echo n; echo p; echo 1; echo $part1_start; echo $part1_end
  echo n; echo p; echo 2; echo $part2_start; echo $part2_end
  echo n; echo p; echo 3; echo $part3_start; echo $part3_end

  [[ "$firmware" == "BIOS" ]] && echo a && echo 1
  echo w
} | fdisk "$disk"

# Wait for partitions
part_prefix=""
[[ "$disk" =~ nvme || "$disk" =~ mmcblk ]] && part_prefix="p"

boot_partition="${disk}${part_prefix}1"
root_partition="${disk}${part_prefix}2"
home_partition="${disk}${part_prefix}3"

print_message "Waiting for partitions..."
for i in {1..60}; do
  [[ -b "$boot_partition" && -b "$root_partition" && -b "$home_partition" ]] && break
  sleep 0.5
done

if [[ ! -b "$boot_partition" || ! -b "$root_partition" || ! -b "$home_partition" ]]; then
  echo "Error: Partitions not detected."
  exit 1
fi

# Format and mount
print_message "Formatting partitions..."
mkfs.ext4 "$boot_partition"
mkfs.ext4 "$root_partition"
mkfs.ext4 "$home_partition"

print_message "Mounting partitions..."
mount "$root_partition" /mnt
mkdir -p /mnt/boot /mnt/home
mount "$boot_partition" /mnt/boot
mount "$home_partition" /mnt/home

# Base system
print_message "Installing base system..."
basestrap /mnt base base-devel runit elogind-runit linux linux-firmware networkmanager networkmanager-runit neovim

print_message "Generating fstab..."
fstabgen -U /mnt >> /mnt/etc/fstab

# Chroot setup
print_message "Chrooting into system..."
artix-chroot /mnt <<EOF
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc

sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
sed -i 's/^#en_US ISO-8859-1/en_US ISO-8859-1/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "$hostname" > /etc/hostname
echo -e "127.0.1.1 \t$hostname.localdomain $hostname" >> /etc/hosts

pacman -S --noconfirm networkmanager networkmanager-runit
ln -s /etc/runit/sv/NetworkManager/ /etc/runit/runsvdir/current

useradd -m -G wheel "$username"
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

ln -s /etc/runit/sv/NetworkManager /etc/runit/runsvdir/default 2>/dev/null || true

if [[ "$firmware" == "UEFI" ]]; then
  pacman -S --noconfirm grub efibootmgr
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
  pacman -S --noconfirm grub
  grub-install --target=i386-pc /dev/$disk_name
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
