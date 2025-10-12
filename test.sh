#!/bin/bash
set -euo pipefail

# Root check
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root."
  exit 1
fi

# Helper: prompt with default
ask() {
  local prompt="$1"
  local default="$2"
  read -rp "$prompt [$default]: " input
  echo "${input:-$default}"
}

# Helper: confirmation with Y/n
confirm() {
  local prompt="$1"
  local default="${2:-no}"
  local yn_format
  [[ "${default,,}" =~ ^(yes|y)$ ]] && yn_format="[Y/n]" || yn_format="[y/N]"
  read -rp "$prompt $yn_format: " answer
  answer="${answer:-$default}"
  [[ "${answer,,}" =~ ^(yes|y)$ ]]
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
confirm "This will erase all data on $disk. Continue?" "no" || exit 1

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
  [[ -z "$continent_matched" ]] && echo "Invalid continent. Try again." && continue

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
  [[ -z "$city_matched" ]] && echo "Invalid city. Try again." && continue

  timezone="$continent_matched/$city_matched"
  break
done

# Disk partitioning
echo "Wiping and partitioning $disk..."
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

part_prefix=""
[[ "$disk" =~ nvme || "$disk" =~ mmcblk ]] && part_prefix="p"
boot_partition="${disk}${part_prefix}1"
root_partition="${disk}${part_prefix}2"
home_partition="${disk}${part_prefix}3"

echo "Waiting for partitions..."
for p in "$boot_partition" "$root_partition" "$home_partition"; do
  while [ ! -b "$p" ]; do sleep 0.5; done
done

# Format partitions
[[ "$firmware" == "UEFI" ]] && mkfs.fat -F32 "$boot_partition" || mkfs.ext4 "$boot_partition"
mkfs.ext4 "$root_partition"
mkfs.ext4 "$home_partition"

# Mount partitions
mount "$root_partition" /mnt
mkdir -p /mnt/boot /mnt/home
mount "$boot_partition" /mnt/boot
mount "$home_partition" /mnt/home

for dir in dev proc sys run; do
  mkdir -p "/mnt/$dir"
  mount --bind "/$dir" "/mnt/$dir"
done

# Install base system
base_packages=(base base-devel runit elogind-runit linux linux-firmware neovim networkmanager networkmanager-runit grub sudo)
[[ "$firmware" == "UEFI" ]] && base_packages+=(efibootmgr)
basestrap /mnt "${base_packages[@]}"
fstabgen -U /mnt > /mnt/etc/fstab

# Set passwords
echo "Set root password:"
while true; do
  read -s -p "Root password: " rootpass1; echo
  read -s -p "Confirm root password: " rootpass2; echo
  [[ "$rootpass1" == "$rootpass2" && -n "$rootpass1" ]] && break || echo "Passwords do not match."
done

echo "Set password for user '$username':"
while true; do
  read -s -p "User password: " userpass1; echo
  read -s -p "Confirm user password: " userpass2; echo
  [[ "$userpass1" == "$userpass2" && -n "$userpass1" ]] && break || echo "Passwords do not match."
done

# Ask for graphical environment
if confirm "Do you want to install the graphical suckless environment?" "yes"; then
  install_env=true
else
  install_env=false
fi

# chroot config
artix-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc

sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "$hostname" > /etc/hostname
echo -e "127.0.1.1\t$hostname.localdomain $hostname" >> /etc/hosts

useradd -m -G wheel,audio "$username"
echo "$username:$userpass1" | chpasswd
echo "root:$rootpass1" | chpasswd

sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
ln -s /etc/runit/sv/NetworkManager /etc/runit/runsvdir/default

if [[ "$firmware" == "UEFI" ]]; then
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
  grub-install --target=i386-pc "$disk"
fi
grub-mkconfig -o /boot/grub/grub.cfg
EOF

# If graphical environment is chosen
if [[ "$install_env" == true ]]; then
  echo "Installing graphical environment inside chroot..."

  artix-chroot /mnt /bin/bash -c "
    pacman -Syu --noconfirm
    pacman -S --noconfirm sudo git gcc make xorg xorg-xinit libx11 libxinerama libxft \
      ttf-dejavu ttf-font-awesome alsa-utils-runit

    su - $username -c '
      mkdir -p ~/.config
      cd ~/.config
      for repo in dwm dmenu st; do
        git clone https://git.suckless.org/\$repo
      done

      sed -i \"s/#define MODKEY Mod1Mask/#define MODKEY Mod4Mask/\" ~/.config/dwm/config.def.h
      rm -f ~/.config/dwm/config.h || true

      for app in dwm dmenu st; do
        cd ~/.config/\$app
        make clean
        make
        sudo make install
      done

      echo \"exec dwm\" > ~/.xinitrc

      cat > ~/.bash_profile <<'BASH'
if [[ -z \$DISPLAY ]] && [[ \$(tty) = /dev/tty1 ]]; then
    startx
fi
BASH
    '

    ln -s /etc/runit/sv/alsa /etc/runit/runsvdir/default || true
  "
fi

# Cleanup
for dir in dev proc sys run; do
  umount -l "/mnt/$dir"
done

echo
echo "Installation complete. You can now reboot."
