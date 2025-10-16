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
while true; do
  echo "Available continents:"
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
    continue
  fi

  echo "Available cities in $continent_matched:"
  mapfile -t cities < <(find "/usr/share/zoneinfo/$continent_matched" -type f -exec basename {} \; | sort)

  # Pick a random default city
  default_city="${cities[RANDOM % ${#cities[@]}]}"
  for city in "${cities[@]}"; do echo "  $city"; done

  city_input=$(ask "City" "$default_city")
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
    continue
  fi
  timezone="$continent_matched/$city_matched"
  break
done

# Calculate partition sizes in sectors
sector_size=$(blockdev --getss "$disk")
total_sectors=$(blockdev --getsz "$disk")

boot_size_mib=512
boot_size_sectors=$(( boot_size_mib * 1024 * 1024 / sector_size ))

remaining_sectors=$(( total_sectors - boot_size_sectors ))

# Split remaining sectors: 75% root, 25% home
root_size_sectors=$(( remaining_sectors * 75 / 100 ))
home_size_sectors=$(( remaining_sectors - root_size_sectors ))

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

echo "Partition layout:"
echo "/boot   : sectors $part1_start - $part1_end (~$boot_size_mib MiB)"
echo "/       : sectors $part2_start - $part2_end (~$((root_size_sectors * sector_size / 1024 / 1024)) MiB)"
echo "/home   : sectors $part3_start - $part3_end (~$((home_size_sectors * sector_size / 1024 / 1024)) MiB)"

echo "Wiping and partitioning $disk..."
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

echo "Waiting for partitions to appear..."

# Improved wait logic: wait up to 30 seconds (adjustable) for partitions
for i in {1..60}; do
  if [ -b "$boot_partition" ] && [ -b "$root_partition" ] && [ -b "$home_partition" ]; then
    break
  fi
  if (( i == 60 )); then
    echo "[ERROR] Timeout: Partitions did not appear after 30 seconds."
    exit 1
  fi
  sleep 0.5
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

echo
echo "Installation complete. Please reboot and remove the installation media."
