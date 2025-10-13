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

# Partition sizing logic
boot_size_mib=512
min_root_size_mib=10240   # 10 GiB minimum root partition
buffer_mib=1024           # 1 GiB buffer for /home

disk_size_bytes=$(blockdev --getsize64 "$disk")
disk_size_mib=$(( disk_size_bytes / 1024 / 1024 ))

if (( disk_size_mib < boot_size_mib + min_root_size_mib + buffer_mib )); then
  echo "Disk too small for installation (need at least $((boot_size_mib + min_root_size_mib + buffer_mib)) MiB)."
  exit 1
fi

root_size_mib=$(( disk_size_mib - boot_size_mib - buffer_mib ))
boot_size="+${boot_size_mib}M"
root_size="+${root_size_mib}M"

echo "Partition sizes:"
echo "  /boot: $boot_size (512MiB)"
echo "  /    : $root_size (~${root_size_mib}MiB)"
echo "  /home : remaining space (~${buffer_mib}MiB buffer reserved)"

echo "Wiping and partitioning $disk..."
wipefs -a "$disk"

# Partitioning using fdisk
if [[ "$firmware" == "UEFI" ]]; then
  table_type="g"
else
  table_type="o"
fi

{
  echo "$table_type"
  echo n; echo 1; echo; echo "$boot_size"
  echo n; echo 2; echo; echo "$root_size"
  echo n; echo 3; echo; echo
  [[ "$firmware" == "BIOS" ]] && echo a && echo 1
  echo w
} | fdisk "$disk"

# Partition device names
part_prefix=""
[[ "$disk" =~ nvme || "$disk" =~ mmcblk ]] && part_prefix="p"

boot_partition="${disk}${part_prefix}1"
root_partition="${disk}${part_prefix}2"
home_partition="${disk}${part_prefix}3"

echo "Waiting for partitions to appear..."
for p in "$boot_partition" "$root_partition" "$home_partition"; do
  while [ ! -b "$p" ]; do sleep 0.5; done
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
