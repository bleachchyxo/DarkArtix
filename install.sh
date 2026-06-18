#!/bin/bash
set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "Run as root"; exit 1; }

firmware=$([ -d /sys/firmware/efi ] && echo "UEFI" || echo "BIOS")

msg() { echo -e "[+] $*"; }

prompt() { read -rp "$1 [$2]: " v; echo "${v:-$2}"; }

confirm() {
  read -rp "$1 [y/N]: " r
  [[ "${r,,}" =~ ^(y|yes)$ ]] || { echo "Aborted."; exit 1; }
}

echo "DarkArtix Installer v0.1"
echo "Firmware: $firmware"

# ---------------- DISK ----------------
msg "Selecting disk"
mapfile -t disks < <(lsblk -dno NAME,SIZE,TYPE | awk '$3=="disk"{print $1, $2}')
((${#disks[@]})) || { echo "No disks found"; exit 1; }

max=0
for d in "${disks[@]}"; do
  s=${d#* }
  (( ${#s} > max )) && max=${#s}
done

for d in "${disks[@]}"; do
  name=${d%% *}
  size=${d#* }
  model=$(lsblk -dn -o MODEL "/dev/$name" 2>/dev/null || echo "")
  printf "  %-6s %-${max}s %s\n" "$name" "$size" "$model"
done

default_disk=${disks[0]%% *}
disk=$(prompt "Disk" "$default_disk")
disk="/dev/$disk"
[[ -b $disk ]] || { echo "Invalid disk"; exit 1; }

confirm "Wipe ALL data on $disk?"

part_prefix=""
[[ "$disk" =~ (nvme|mmcblk) ]] && part_prefix="p"

boot=${disk}${part_prefix}1
root=${disk}${part_prefix}2
home=${disk}${part_prefix}3

# ---------------- TIMEZONE ----------------
msg "Timezone"

zone_root=/usr/share/zoneinfo

while true; do
  echo "Continents: Africa America Antarctica Asia Atlantic Australia Europe Mexico Pacific US"
  region=$(prompt "Continent" "America")
  region=${region^}

  [[ -d "$zone_root/$region" ]] || { echo "Invalid"; continue; }

  mapfile -t cities < <(find "$zone_root/$region" -maxdepth 1 -mindepth 1 -type d -printf "%f\n")

  city=$(prompt "City" "${cities[0]}")

  match=""
  for c in "${cities[@]}"; do
    [[ "${c,,}" == "${city,,}" ]] && match=$c && break
  done

  [[ -z "$match" ]] && { echo "Invalid city"; continue; }

  timezone="$region/$match"
  break
done

# ---------------- USER ----------------
msg "User setup"

valid_name() { [[ $1 =~ ^[a-z_][a-z0-9_-]*$ ]]; }

hostname=$(prompt "Hostname" "artix")
while ! valid_name "$hostname"; do
  echo "Invalid hostname"
  hostname=$(prompt "Hostname" "artix")
done

username=$(prompt "Username" "user")
while ! valid_name "$username"; do
  echo "Invalid username"
  username=$(prompt "Username" "user")
done

read -rsp "Root password: " rootpass; echo
read -rsp "Confirm: " rootpass2; echo
[[ "$rootpass" == "$rootpass2" && -n "$rootpass" ]] || exit 1

read -rsp "User password: " userpass; echo
read -rsp "Confirm: " userpass2; echo
[[ "$userpass" == "$userpass2" && -n "$userpass" ]] || exit 1

# ---------------- DISK SIZE ----------------
diskname=$(basename "$disk")
size_gb=$(( $(cat /sys/block/$diskname/size) * $(cat /sys/block/$diskname/queue/hw_sector_size) / 1024 / 1024 / 1024 ))

case $size_gb in
  [0-9]*) boot_size=1; root_size=4 ;;
  1[0-9]*) boot_size=1; root_size=6 ;;
  2[0-9]|3[0-9]) boot_size=1; root_size=8 ;;
  [4-9][0-9]) boot_size=1; root_size=20 ;;
  *) boot_size=1; root_size=30 ;;
esac

# ---------------- WIPE ----------------
umount -R /mnt 2>/dev/null || true
wipefs -af "$disk" || true

# ---------------- PARTITION ----------------
if [[ "$firmware" == "UEFI" ]]; then
fdisk "$disk" <<EOF
g
n
1

+${boot_size}G
t
1
n
2

+${root_size}G
n
3


w
EOF
else
fdisk "$disk" <<EOF
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
fi

partprobe "$disk"
udevadm settle

# wait partitions (fix race condition)
for i in {1..10}; do
  [[ -b "$root" ]] && break
  sleep 1
done

# ---------------- FORMAT ----------------
[[ "$firmware" == "UEFI" ]] && mkfs.fat -F32 "$boot" || mkfs.ext4 -F "$boot"
mkfs.ext4 -F "$root"
mkfs.ext4 -F "$home"

mount "$root" /mnt
mkdir -p /mnt/boot /mnt/home
mount "$boot" /mnt/boot
mount "$home" /mnt/home

# ---------------- INSTALL ----------------
base=(base base-devel runit elogind-runit linux linux-firmware neovim networkmanager networkmanager-runit grub)
[[ "$firmware" == "UEFI" ]] && base+=(efibootmgr)

basestrap /mnt "${base[@]}"
fstabgen -U /mnt >> /mnt/etc/fstab

# ---------------- CHROOT ----------------
artix-chroot /mnt /bin/bash <<EOF
set -e

ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc

sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "$hostname" > /etc/hostname
cat > /etc/hosts <<H
127.0.0.1 localhost
127.0.1.1 $hostname.localdomain $hostname
H

useradd -m -G wheel "$username"
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

ln -sf /etc/runit/sv/NetworkManager /etc/runit/runsvdir/default || true

if [[ "$firmware" == "UEFI" ]]; then
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
  grub-install --target=i386-pc "$disk"
fi

grub-mkconfig -o /boot/grub/grub.cfg

echo "root:$rootpass" | chpasswd
echo "$username:$userpass" | chpasswd
EOF

unset rootpass rootpass2 userpass userpass2

echo
msg "Installation complete"
