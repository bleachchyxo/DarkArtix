#!/bin/bash
set -euo pipefail

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root."
  exit 1
fi

firmware="BIOS"
[ -d /sys/firmware/efi ] && firmware="UEFI"

# Function to print colored messages
message() {
  local color="$1"
  local msg="$2"
  case "$color" in
    green)  echo -e "\033[32m[+]\033[0m $msg" ;;
    yellow) echo -e "\033[33m[+]\033[0m $msg" ;;
    blue)   echo -e "\033[34m[+]\033[0m $msg" ;;
    *)      echo "[+] $msg" ;;
  esac
}

# Prompt with default value
default_prompt() {
  local prompt="$1"
  local default="$2"
  read -rp "$prompt [$default]: " input
  echo "${input:-$default}"
}

# Yes/No confirmation prompt with default answer
confirmation() {
  local prompt="$1"
  local default="${2:-no}"
  local yn_format
  [[ "${default,,}" =~ ^(yes|y)$ ]] && yn_format="[Y/n]" || yn_format="[y/N]"
  read -rp "$prompt $yn_format: " answer
  answer="${answer:-$default}"
  [[ "${answer,,}" =~ ^(yes|y)$ ]] || { echo "Aborted."; exit 1; }
}

echo "DarkArtix Installer v0.1"
echo "Firmware: $firmware"

# Choosing a disk to install
message blue "Choosing a disk"
echo "Available disks:"
mapfile -t available_disks < <(lsblk -dno NAME,SIZE,TYPE | awk '$3=="disk" && $1!~/loop|ram/ {print $1, $2}')
((${#available_disks[@]})) || { echo "No disks detected."; exit 1; }

max_size_length=0
for disk_entry in "${available_disks[@]}"; do
  size_part="${disk_entry#* }"
  (( ${#size_part} > max_size_length )) && max_size_length=${#size_part}
done

for disk_entry in "${available_disks[@]}"; do
  disk_name="${disk_entry%% *}"
  disk_size="${disk_entry#* }"
  disk_path="/dev/$disk_name"
  partition_type=$(lsblk -dn -o PTTYPE "$disk_path")
  disk_model=$(fdisk -l "$disk_path" 2>/dev/null | awk -F: '/Disk model/ {gsub(/^ +/,"",$2); print $2}')
  printf "  %-4s %-${max_size_length}s (%s)\n" "$disk_name" "$disk_size" "${disk_model:-$partition_type}"
done

default_disk="${available_disks[0]%% *}"
disk_choice=$(default_prompt "Choose a disk to install" "$default_disk")
disk_path="/dev/$disk_choice"

if [[ -z "${disk_choice:-}" || ! -b "$disk_path" ]]; then
  echo "Invalid or missing disk selection."
  exit 1
fi

confirmation "This will erase all data on $disk_path. Continue?" "no"

# setting region
message blue "Setting the region"
zone_root="/usr/share/zoneinfo"

while true; do
  echo "Available continents:"
  echo "Africa  America  Antarctica  Asia  Atlantic  Australia  Europe  Mexico  Pacific  US"
  region="$(tr '[:upper:]' '[:lower:]' <<< "$(default_prompt "Continent" "America")")"
  region="${region^}"
  [[ -d "$zone_root/$region" || -d "$zone_root/${region^^}" ]] || { echo "Invalid option."; continue; }
  region=$( [[ -d "$zone_root/$region" ]] && echo "$region" || echo "${region^^}" )

  region_path="$zone_root/$region"
  timezone="$region"

  while true; do
    echo "Available cities in $timezone:"
    ls "$region_path"
    cities=($(ls "$region_path"))
    city=$(default_prompt "City/Timezone" "${cities[RANDOM % ${#cities[@]}]}")

    chosen_city=""
    for e in "${cities[@]}"; do [[ "${e,,}" == "${city,,}" ]] && chosen_city="$e" && break; done
    [[ -z "$chosen_city" ]] && { echo "Invalid option."; continue; }

    region_path="$region_path/$chosen_city"
    timezone="$timezone/$chosen_city"
    [[ -f "$region_path" ]] && break 2
  done
done

# Hostname and username
message blue "Hostname and username"
hostname=$(default_prompt "Hostname" "artix")
username=$(default_prompt "Username" "user")

# Setting password for root and user
message blue "Passwords"
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

# formatting disk and creating partitions
disk_name=$(basename "$disk_path")
total_gb=$(( $(< /sys/block/$disk_name/size) * $(< /sys/block/$disk_name/queue/hw_sector_size) / 1024 / 1024 / 1024 ))

case $total_gb in
  [0-9]) boot_size=0.5 root_size=4 ;;
  1[0-9]) boot_size=0.5 root_size=6 ;;
  2[0-9]|3[0-9]) boot_size=1 root_size=8 ;;
  [4-9][0-9]) boot_size=1 root_size=20 ;;
  1[0-9][0-9]|*) boot_size=1 root_size=30 ;;
esac

for partition in $(lsblk -ln -o NAME "$disk_path" | tail -n +2); do
    mount_point=$(lsblk -ln -o MOUNTPOINT "/dev/$partition")
    [ -n "$mount_point" ] && umount "/dev/$partition"
done

fdisk "$disk_path" <<EOF
o
n
p
1

+${boot_size}G
n
p
2

+${root_size}G
n
p
3


w
EOF

sleep 2

if [ "$firmware" = "UEFI" ]; then
  mkfs.fat -F32 "${disk_path}1"
else
  mkfs.ext4 -F "${disk_path}1"
fi
mkfs.ext4 -F "${disk_path}2"
mkfs.ext4 -F "${disk_path}3"

# Mounting partition directories
mount "${disk_path}2" /mnt
mkdir -p /mnt/boot /mnt/home
mount "${disk_path}1" /mnt/boot
mount "${disk_path}3" /mnt/home

# Installing the base system
base_packages=(base base-devel runit elogind-runit linux linux-firmware neovim networkmanager networkmanager-runit grub)
[[ "$firmware" == "UEFI" ]] && base_packages+=(efibootmgr)

basestrap /mnt "${base_packages[@]}"
fstabgen -U /mnt >> /mnt/etc/fstab

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
message green "Installation complete. Please reboot and remove the installation media."
