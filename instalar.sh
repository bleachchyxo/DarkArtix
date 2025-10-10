#!/bin/bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Run as root."
  exit 1
fi

# === Helper ===
prompt_default() {
  local prompt="$1"
  local default="$2"
  local input
  read -rp "$prompt [$default]: " input
  echo "${input:-$default}"
}

# === Firmware ===
firmware="BIOS"
[ -d /sys/firmware/efi ] && firmware="UEFI"
echo "[+] Firmware detected: $firmware"

# === Select Disk ===
echo "[+] Available disks:"
lsblk -dn -o NAME,SIZE,MODEL | while read -r name size model; do
  echo "  /dev/$name  $size  $model"
done
default_disk=$(lsblk -dn -o NAME | head -n1)
disk=$(prompt_default "Choose install disk" "$default_disk")
install_disk="/dev/$disk"
if [ ! -b "$install_disk" ]; then
  echo "Invalid disk $install_disk"
  exit 1
fi
confirm=$(prompt_default "Confirm install to $install_disk? (yes/no)" "yes")
[[ "$confirm" =~ ^(yes|y)$ ]] || { echo "Aborted."; exit 1; }

# === Get Disk Size ===
disk_bytes=$(lsblk -b -dn -o SIZE "$install_disk")
disk_size_mib=$((disk_bytes / 1024 / 1024))

# === Partition Sizes ===
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

boot="${install_disk}1"
root="${install_disk}2"
home="${install_disk}3"

sleep 1

# === Format Partitions ===
echo "[+] Formatting partitions"
if [ "$firmware" = "UEFI" ]; then
  mkfs.fat -F32 "$boot"
else
  mkfs.ext4 "$boot"
fi
mkfs.ext4 "$root"
mkfs.ext4 "$home"

# === Mount ===
echo "[+] Mounting partitions"
mount "$root" /mnt
mkdir -p /mnt/boot /mnt/home
mount "$boot" /mnt/boot
mount "$home" /mnt/home

# === Install base ===
echo "[+] Installing base system"
basestrap /mnt base base-devel runit elogind-runit linux linux-firmware neovim

# === Generate fstab ===
fstabgen -U /mnt > /mnt/etc/fstab

# === Chroot ===
artix-chroot /mnt /bin/bash <<EOF
set -e

# === Timezone ===
echo "[+] Setting timezone"
continent="America"
country="New_York"
ln -sf /usr/share/zoneinfo/\$continent/\$country /etc/localtime
hwclock --systohc

# === Locale ===
echo "[+] Configuring locale"
sed -i '/^#en_US.UTF-8 UTF-8/s/^#//' /etc/locale.gen
sed -i '/^#en_US ISO-8859-1/s/^#//' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# === Hostname and hosts ===
echo "[+] Setting hostname"
read -rp "Enter hostname [artix]: " hostname_input
hostname="\${hostname_input:-artix}"
echo "\$hostname" > /etc/hostname
cat >> /etc/hosts <<EOL
127.0.0.1        localhost
::1              localhost
127.0.1.1        \$hostname.localdomain \$hostname
EOL

# === Sudoers ===
echo "[+] Configuring sudoers"
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# === Create user ===
echo "[+] Creating user"
read -rp "Enter username [user]: " user_input
user="\${user_input:-user}"
useradd -m -G wheel "\$user"
echo "Set password for \$user:"
passwd "\$user"

# === NetworkManager ===
echo "[+] Installing NetworkManager"
pacman -S --noconfirm networkmanager networkmanager-runit
ln -s /etc/runit/sv/NetworkManager /etc/runit/runsvdir/current
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/00-macrandomize.conf <<EOL
[device]
wifi.scan-rand-mac-address=yes

[connection]
wifi.cloned-mac-address=stable
ethernet.cloned-mac-address=stable
EOL

# === Install GRUB ===
echo "[+] Installing GRUB"
if [ "$firmware" = "UEFI" ]; then
  pacman -S --noconfirm grub efibootmgr
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
  pacman -S --noconfirm grub
  grub-install --target=i386-pc "$install_disk"
fi
grub-mkconfig -o /boot/grub/grub.cfg

# === ALSA ===
pacman -S --noconfirm alsa-utils alsa-utils-runit
ln -s /etc/runit/sv/alsa /etc/runit/runsvdir/default/

EOF

# === Post-chroot dwm install ===
echo "[+] Installing suckless tools (dwm, dmenu, st)"
sudo -u "$user" bash <<'EOS'
cd ~
mkdir -p .config
cd .config
git clone https://git.suckless.org/dwm
git clone https://git.suckless.org/dmenu
git clone https://git.suckless.org/st
for dir in dwm dmenu st; do
  cd "$dir"
  make install
  cd ..
done
echo "exec dwm" > ~/.xinitrc

# Startx auto on tty1
cat > ~/.bash_profile <<EOF
if [[ -z \$DISPLAY ]] && [[ \$(tty) == /dev/tty1 ]]; then
  startx
fi
EOF
EOS

echo "[+] Installation complete. Reboot now."
