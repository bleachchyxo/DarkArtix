#!/bin/bash
set -e

# Check root
if [ "$EUID" -ne 0 ]; then
  echo "Run as root"
  exit 1
fi

# Detect UEFI or BIOS
if [ -d /sys/firmware/efi ]; then
  firmware="UEFI"
else
  firmware="BIOS"
fi
echo "[+] Detected firmware: $firmware"

# List disks
echo "[+] Available disks:"
lsblk -d -e7 -o NAME,SIZE,MODEL | grep -v loop
echo

# Select install disk
read -rp "Enter disk to install to (e.g., sda): " disk
install_disk="/dev/$disk"

if [ ! -b "$install_disk" ]; then
  echo "Invalid disk."
  exit 1
fi

# Confirm
echo "WARNING: This will erase everything on $install_disk"
read -rp "Type 'YES' to confirm: " confirm
if [ "$confirm" != "YES" ]; then
  echo "Aborted."
  exit 1
fi

# Partition mode
echo "[1] Default partitioning"
echo "[2] Advanced (manual) partitioning"
read -rp "Select partitioning mode [1/2]: " part_mode

if [ "$part_mode" = "2" ]; then
  cfdisk "$install_disk"
else
  # Default partitioning
  wipefs -a "$install_disk"
  parted -s "$install_disk" mklabel gpt

  parted -s "$install_disk" mkpart ESP fat32 1MiB 513MiB
  parted -s "$install_disk" set 1 boot on
  parted -s "$install_disk" mkpart root ext4 513MiB 30.5GiB
  parted -s "$install_disk" mkpart home ext4 30.5GiB 100%

  boot="${install_disk}1"
  root="${install_disk}2"
  home="${install_disk}3"

  if [ "$firmware" = "UEFI" ]; then
    mkfs.fat -F32 "$boot"
  else
    mkfs.ext4 "$boot"
  fi

  mkfs.ext4 "$root"
  mkfs.ext4 "$home"
fi

# Mount partitions
mount "$root" /mnt
mkdir -p /mnt/boot /mnt/home
mount "$boot" /mnt/boot
mount "$home" /mnt/home

# Install base system
basestrap /mnt base base-devel runit elogind-runit linux linux-firmware neovim git

# fstab
fstabgen -U /mnt >> /mnt/etc/fstab

# Chroot
artix-chroot /mnt /bin/bash <<EOF

# Set timezone
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
hwclock --systohc

# Set locale
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Hostname
read -rp "Enter hostname: " HOSTNAME
echo "$HOSTNAME" > /etc/hostname
cat <<HCONF >> /etc/hosts
127.0.0.1    localhost
::1          localhost
127.0.1.1    ${HOSTNAME}.localdomain ${HOSTNAME}
HCONF

# Sudo setup
pacman -S --noconfirm sudo
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Create user
read -rp "Enter username: " username
useradd -m -G wheel "$username"
passwd "$username"

# GRUB install
if [ "$firmware" = "UEFI" ]; then
  pacman -S --noconfirm grub efibootmgr
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
  pacman -S --noconfirm grub
  grub-install --target=i386-pc "$install_disk"
fi
grub-mkconfig -o /boot/grub/grub.cfg

# NetworkManager
pacman -S --noconfirm networkmanager networkmanager-runit
ln -s /etc/runit/sv/NetworkManager /etc/runit/runsvdir/default

# ALSA sound
pacman -S --noconfirm alsa-utils alsa-utils-runit
ln -s /etc/runit/sv/alsa /etc/runit/runsvdir/default

# DWM install
cd /home/"$username"
sudo -u "$username" mkdir -p /home/"$username"/.config
cd /home/"$username"/.config
sudo -u "$username" git clone https://git.suckless.org/dwm
sudo -u "$username" git clone https://git.suckless.org/dmenu
sudo -u "$username" git clone https://git.suckless.org/st

for pkg in dwm dmenu st; do
  cd /home/"$username"/.config/$pkg
  sudo -u "$username" make install
done

# Autostart dwm
sudo -u "$username" bash -c 'echo "exec dwm" >> ~/.xinitrc'
sudo -u "$username" bash -c 'cat <<PROFILE > ~/.bash_profile
if [[ -z \$DISPLAY ]] && [[ \$(tty) = /dev/tty1 ]]; then
  startx
fi
PROFILE'

EOF

echo "[+] Installation complete! You can now reboot."
