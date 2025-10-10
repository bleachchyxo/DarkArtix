#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Run this script as root."
  exit 1
fi

# ====== Detect Firmware ======
if [ -d /sys/firmware/efi ]; then
  firmware="UEFI"
else
  firmware="BIOS"
fi
echo "[+] Firmware detected: $firmware"

# ====== Select Target Disk ======
echo
echo "[+] Available disks:"
lsblk -d -e7 -o NAME,SIZE,MODEL | grep -v loop | while read -r line; do
  dev=$(echo "$line" | awk '{print $1}')
  size=$(echo "$line" | awk '{print $2}')
  model=$(echo "$line" | cut -d' ' -f3-)
  echo "  /dev/$dev - $size - $model"
done

default_disk=$(lsblk -d -e7 -o NAME | grep -v loop | head -n1)
read -rp "Enter install disk [default: /dev/$default_disk]: " disk_input
disk="${disk_input:-$default_disk}"
install_disk="/dev/$disk"

if [ ! -b "$install_disk" ]; then
  echo "Invalid disk: $install_disk"
  exit 1
fi

# Confirm selection with default prompt
read -rp "Install to $install_disk? [Y/n]: " confirm
confirm="${confirm,,}"  # to lowercase
if [[ "$confirm" =~ ^(n|no)$ ]]; then
  echo "Aborted."
  exit 1
fi

# ====== Auto Partition (Default Layout) ======
echo "[+] Partitioning $install_disk..."

wipefs -a "$install_disk"
echo -e "g\nn\n1\n\n+512M\nt\n1\nn\n2\n\n+30G\nn\n3\n\n\nw" | fdisk "$install_disk"

boot="${install_disk}1"
root="${install_disk}2"
home="${install_disk}3"

sleep 1

# ====== Format Partitions ======
echo "[+] Formatting partitions..."

if [ "$firmware" = "UEFI" ]; then
  mkfs.fat -F32 "$boot"
else
  mkfs.ext4 "$boot"
fi

mkfs.ext4 "$root"
mkfs.ext4 "$home"

# ====== Mount Partitions ======
echo "[+] Mounting partitions..."

mount "$root" /mnt
mkdir -p /mnt/boot /mnt/home
mount "$boot" /mnt/boot
mount "$home" /mnt/home

# ====== Base Installation ======
echo "[+] Installing base system..."
basestrap /mnt base base-devel runit elogind-runit linux linux-firmware neovim git

fstabgen -U /mnt >> /mnt/etc/fstab

# ====== Enter chroot ======
artix-chroot /mnt /bin/bash <<'EOF_CHROOT'

# ====== Timezone Selection ======
echo "[*] Timezone setup..."

CONTINENTS=$(ls /usr/share/zoneinfo | grep -v Etc | grep -v posix | grep -v right)
default_continent="America"
echo "Available continents:"
echo "$CONTINENTS" | nl
read -rp "Continent [default: $default_continent]: " cont_input
continent="${cont_input:-$default_continent}"

COUNTRIES=$(ls "/usr/share/zoneinfo/$continent" 2>/dev/null)
default_country="New_York"
echo "Available cities in $continent:"
echo "$COUNTRIES" | nl
read -rp "City [default: $default_country]: " city_input
city="${city_input:-$default_country}"

ln -sf "/usr/share/zoneinfo/$continent/$city" /etc/localtime
hwclock --systohc

# ====== Locale ======
echo "[*] Setting locale..."
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# ====== Hostname ======
read -rp "Enter hostname [default: artix]: " hn
hostname="${hn:-artix}"
echo "$hostname" > /etc/hostname

cat <<EOF_HOSTS >> /etc/hosts
127.0.0.1    localhost
::1          localhost
127.0.1.1    ${hostname}.localdomain ${hostname}
EOF_HOSTS

# ====== Sudo Setup ======
echo "[*] Installing sudo and enabling wheel group..."
pacman -S --noconfirm sudo
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# ====== User Setup ======
read -rp "New username [default: user]: " uname
username="${uname:-user}"
useradd -m -G wheel "$username"
passwd "$username"

# ====== GRUB Bootloader ======
if [ "$firmware" = "UEFI" ]; then
  pacman -S --noconfirm grub efibootmgr
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
  pacman -S --noconfirm grub
  grub-install --target=i386-pc "$install_disk"
fi
grub-mkconfig -o /boot/grub/grub.cfg

# ====== NetworkManager ======
pacman -S --noconfirm networkmanager networkmanager-runit
ln -s /etc/runit/sv/NetworkManager /etc/runit/runsvdir/default

# ====== ALSA Audio ======
pacman -S --noconfirm alsa-utils alsa-utils-runit
ln -s /etc/runit/sv/alsa /etc/runit/runsvdir/default

# ====== DWM, dmenu, st ======
echo "[*] Installing DWM..."
cd /home/"$username"
sudo -u "$username" mkdir -p .config
cd .config
sudo -u "$username" git clone https://git.suckless.org/dwm
sudo -u "$username" git clone https://git.suckless.org/dmenu
sudo -u "$username" git clone https://git.suckless.org/st

for pkg in dwm dmenu st; do
  cd "/home/$username/.config/$pkg"
  sudo -u "$username" make install
done

# ====== Autostart X and DWM ======
sudo -u "$username" bash -c 'echo "exec dwm" > ~/.xinitrc'
sudo -u "$username" bash -c 'cat <<EOF_BASH > ~/.bash_profile
if [[ -z \$DISPLAY ]] && [[ \$(tty) = /dev/tty1 ]]; then
  startx
fi
EOF_BASH'

EOF_CHROOT

echo "[+] Installation complete. You can now reboot."
