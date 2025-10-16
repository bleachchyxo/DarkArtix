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
print_message "Firmware detected: $firmware"

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

# List cities with better formatting (one more space apart)
cols=4
for i in "${!cities[@]}"; do
  if (( i % cols == 0 )); then
    echo
  fi
  printf "%-15s" "${cities[$i]}"  # Adding extra space for better separation
done
echo

# Pick city and timezone
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

# Partition sizes: 1G for /boot, 30G for /, and the rest for /home
# Dynamically calculate sizes based on total disk size
disk_size_gb=$(lsblk -bno SIZE "$disk" | awk '{print int($1/1024/1024/1024)}')

# Calculate partition sizes (keeping partitions proportional)
boot_size_gb=1
root_size_gb=30
home_size_gb=$(( disk_size_gb - boot_size_gb - root_size_gb ))

# Safety check to ensure home partition isn't negative
if (( home_size_gb < 1 )); then
  home_size_gb=1
  root_size_gb=$(( disk_size_gb - boot_size_gb - home_size_gb ))
fi

# Display partition sizes
print_message "Disk size: $disk_size_gb GB"
print_message "/boot size: $boot_size_gb GB"
print_message "/ size: $root_size_gb GB"
print_message "/home size: $home_size_gb GB"

# Calculate partition sizes in sectors (based on disk size)
sector_size=$(blockdev --getss "$disk")
total_sectors=$(blockdev --getsz "$disk")

boot_size_sectors=$(( boot_size_gb * 1024 * 1024 * 1024 / sector_size ))
root_size_sectors=$(( root_size_gb * 1024 * 1024 * 1024 / sector_size ))
home_size_sectors=$(( home_size_gb * 1024 * 1024 * 1024 / sector_size ))

# Ensure the partition sizes do not exceed the disk space
if (( boot_size_sectors + root_size_sectors + home_size_sectors > total_sectors )); then
  print_message "[ERROR] Partition sizes exceed disk space. Adjusting sizes..."
  home_size_sectors=$(( total_sectors - boot_size_sectors - root_size_sectors ))
fi

# Partition start and end sectors (start at sector 2048 for alignment)
part1_start=2048
part1_end=$(( part1_start + boot_size_sectors - 1 ))

part2_start=$(( part1_end + 1 ))
part2_end=$(( part2_start + root_size_sectors - 1 ))

part3_start=$(( part2_end + 1 ))
part3_end=$(( part3_start + home_size_sectors - 1 ))

# Safety check to not exceed disk size
if (( part3_end > total_sectors )); then
  part3_end=$(( total_sectors - 1 ))
fi

# Show partition layout
print_message "Partition layout:"
echo "/boot   : sectors $part1_start - $part1_end (~$boot_size_gb GB)"
echo "/       : sectors $part2_start - $part2_end (~$root_size_gb GB)"
echo "/home   : sectors $part3_start - $part3_end (~$home_size_gb GB)"

# Wipe existing data and create partitions using fdisk
print_message "Wiping and partitioning $disk..."
wipefs -a "$disk"

# Partitioning using fdisk
{
  if [[ "$firmware" == "UEFI" ]]; then
    echo g
  else
    echo o
  fi

  # /boot
  echo n
  echo p
  echo 1
  echo $part1_start
  echo $part1_end

  # /
  echo n
  echo p
  echo 2
  echo $part2_start
  echo $part2_end

  # /home
  echo n
  echo p
  echo 3
  echo $part3_start
  echo $part3_end

  # Mark bootable if BIOS
  if [[ "$firmware" == "BIOS" ]]; then
    echo a
    echo 1
  fi

  echo w
} | fdisk "$disk"

# Partition device names
part_prefix=""
[[ "$disk" =~ nvme || "$disk" =~ mmcblk ]] && part_prefix="p"

boot_partition="${disk}${part_prefix}1"
root_partition="${disk}${part_prefix}2"
home_partition="${disk}${part_prefix}3"

# Wait for partitions to appear
print_message "Waiting for partitions to appear..."
for i in {1..60}; do
  if [ -b "$boot_partition" ] && [ -b "$root_partition" ] && [ -b "$home_partition" ]; then
    break
  fi
  sleep 0.5
done

# If partitions are not detected within 30 seconds, exit with error
if [ ! -b "$boot_partition" ] || [ ! -b "$root_partition" ] || [ ! -b "$home_partition" ]; then
  echo "Error: Partitions not detected in time."
  exit 1
fi

# Format and mount partitions
print_message "Formatting partitions..."
mkfs.ext4 "$boot_partition"
mkfs.ext4 "$root_partition"
mkfs.ext4 "$home_partition"

mount "$root_partition" /mnt
mkdir -p /mnt/boot /mnt/home
mount "$boot_partition" /mnt/boot
mount "$home_partition" /mnt/home

# Install the base system
print_message "Installing the base system..."
artix-chroot /mnt basestrap base base-devel runit elogind-runit linux linux-firmware networkmanager networkmanager-runit neovim

# Generate fstab
print_message "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Set timezone
print_message "Setting timezone..."
artix-chroot /mnt ln -sf /usr/share/zoneinfo/$timezone /etc/localtime

# Localization setup
print_message "Configuring locales..."
artix-chroot /mnt locale-gen
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf

# Set hostname
echo "$hostname" > /mnt/etc/hostname
artix-chroot /mnt ln -s /etc/runit/sv/NetworkManager/ /etc/runit/runsvdir/current

# Set root password
root_password=$(ask "Root password" "root")
artix-chroot /mnt useradd -m -G wheel "$username"
echo "$username:$root_password" | artix-chroot /mnt chpasswd

# Install and configure bootloader
print_message "Installing bootloader..."
if [[ "$firmware" == "UEFI" ]]; then
  artix-chroot /mnt pacman -S grub efibootmgr
  artix-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
  artix-chroot /mnt pacman -S grub
  artix-chroot /mnt grub-install --target=i386-pc /dev/sda
fi
artix-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# Finish up
print_message "Installation complete. Please reboot and remove the installation media."
