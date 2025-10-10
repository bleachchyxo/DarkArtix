#!/bin/bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Run this script as root."
  exit 1
fi

# === Helper: prompt with default ===
prompt_default() {
  local prompt="$1"
  local default="$2"
  local input
  read -rp "$prompt [$default]: " input
  echo "${input:-$default}"
}

# === Detect firmware ===
firmware="BIOS"
[ -d /sys/firmware/efi ] && firmware="UEFI"
echo "[+] Firmware: $firmware"

# === Show available disks ===
echo "[+] Available disks:"
lsblk -dn -o NAME,SIZE,MODEL | while read -r name size model; do
  echo "  /dev/$name  $size  $model"
done
default_disk=$(lsblk -dn -o NAME | head -n1)
disk=$(prompt_default "Choose install disk" "$default_disk")
install_disk="/dev/$disk"

if [ ! -b "$install_disk" ]; then
  echo "Invalid disk: $install_disk"
  exit 1
fi

# === Confirm disk erase ===
echo "!!! This will ERASE ALL DATA on $install_disk !!!"
confirm=$(prompt_default "Are you sure? Type YES to continue" "no")
if ! [[ "$confirm" =~ ^[Yy][Ee][Ss]$ ]]; then
  echo "Aborted."
  exit 1
fi

# === Hostname and username ===
hostname=$(prompt_default "Enter hostname" "artix")
username=$(prompt_default "Enter username" "user")

# === Ask for passwords upfront ===
echo "[+] Set root password"
while true; do
  read -rsp "New root password: " root_pass1; echo
  read -rsp "Confirm root password: " root_pass2; echo
  [ "$root_pass1" = "$root_pass2" ] && break
  echo "Passwords do not match. Try again."
done

echo "[+] Set password for $username"
while true; do
  read -rsp "New password for $username: " user_pass1; echo
  read -rsp "Confirm password for $username: " user_pass2; echo
  [ "$user_pass1" = "$user_pass2" ] && break
  echo "Passwords do not match. Try again."
done

# === Partitioning ===
disk_bytes=$(lsblk -b -dn -o SIZE "$install_disk")
disk_size_mib=$((disk_bytes / 1024 / 1024))
if [ "$disk_size_mib" -ge 35840 ]; then
  boot_end="+1G"
  root_end="+30G"
else
  boot_end="+1G"
  usable=$((disk_size_mib - 1024))
  root_end="+$((usable * 70 / 100))M"
fi

echo "[+] Partitioning $install_disk"
wipefs -a "$install_disk"
{
  echo g
  echo n; echo; echo; echo "$boot_end"
  if [ "$firmware" = "UEFI" ]; then
    echo t; echo 1; echo ef00
  else
    echo t; echo 1; echo 83
  fi
  echo n; echo; echo; echo "$root_end"
  echo n; echo; echo; echo
  echo w
} | fdisk "$install_disk"

if [[ "$install_disk" == *"nvme"* ]]; then
  boot="${install_disk}p1"
  root="${install_disk}p2"
  home="${install_disk}p3"
else
  boot="${install_disk}1"
  root="${install_disk}2"
  home="${install_disk}3"
fi

# === Format partitions ===
echo "[+] Formatting partitions"
[ "$firmware" = "UEFI" ] && mkfs.fat -F32 "$boot" || mkfs.ext4 "$boot"
mkfs.ext4 "$root"
mkfs.ext4 "$home"

# === Mounting ===
echo "[+] Mounting"
mount "$root" /mnt
mkdir -p /mnt/boot /mnt/home
mount "$boot" /mnt/boot
mount "$home" /mnt/home

# === Install base system ===
echo "[+] Installing base system"
basestrap /mnt base base-devel runit elogind-runit linux linux-firmware neovim xorg-server xorg-xinit git

# === Generate fstab ===
fstabgen -U /mnt > /mnt/etc/fstab

# === Chroot configuration ===
artix-chroot /mnt /bin/bash <<EOF
set -e

# Timezone and locale
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
hwclock --systohc
sed -i '/^#en_US.UTF-8 UTF-8/s/^#//' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Hostname
echo "$hostname" > /etc/hostname
cat > /etc/hosts <<EOL
127.0.0.1       localhost
::1             localhost
127.0.1.1       $hostname.localdomain $hostname
EOL

# Sudoers
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Set passwords
echo "root:$root_pass1" | chpasswd
useradd -m -G wheel "$username"
echo "$username:$user_pass1" | chpasswd

# Network
pacman -S --noconfirm networkmanager networkmanager-runit
ln -s /etc/runit/sv/NetworkManager /etc/runit/runsvdir/default

# MAC randomization
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/00-macrandomize.conf <<EOL
[device]
wifi.scan-rand-mac-address=yes
[connection]
wifi.cloned-mac-address=stable
ethernet.cloned-mac-address=stable
EOL

# Bootloader
if [ "$firmware" = "UEFI" ]; then
  pacman -S --noconfirm grub efibootmgr
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
  pacman -S --noconfirm grub
  grub-install --target=i386-pc "$install_disk"
fi
grub-mkconfig -o /boot/grub/grub.cfg

# Audio
pacman -S --noconfirm alsa-utils alsa-utils-runit
ln -s /etc/runit/sv/alsa /etc/runit/runsvdir/default
EOF

# === Install dwm, dmenu, st ===
echo "[+] Installing suckless tools"
runuser -u "$username" -- bash <<EOS
cd ~
mkdir -p .config && cd .config
git clone https://git.suckless.org/dwm
git clone https://git.suckless.org/dmenu
git clone https://git.suckless.org/st
for dir in dwm dmenu st; do
  cd "\$dir"
  make install
  cd ..
done
echo "exec dwm" > ~/.xinitrc

cat > ~/.bash_profile <<EOF
if [[ -z \$DISPLAY ]] && [[ \$(tty) == /dev/tty1 ]]; then
  startx
fi
EOF
EOS

echo "[✔] Installation complete! You can now 'reboot'."
