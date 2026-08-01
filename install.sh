#!/bin/bash
set -euo pipefail

msg() { echo -e "\033[32m[+]\033[0m $1"; }
ask() { local p="$1" d="$2"; read -rp "$p [$d]: " r; echo "${r:-$d}"; }
confirm() {
  read -rp "$1 [y/N]: " a
  [[ "${a,,}" =~ ^y ]] || { echo "Aborted."; exit 1; }
}

check_root() {
  [[ $EUID -eq 0 ]] || { echo "Please run as root."; exit 1; }
}

detect_firmware() {
  [[ -d /sys/firmware/efi ]] && echo UEFI || echo BIOS
}

select_disk() {
  echo "Available disks:" >&2
  mapfile -t disks < <(lsblk -dno NAME,SIZE,TYPE | awk '$3=="disk" && $1!~/loop|ram/ {print $1, $2}')
  ((${#disks[@]})) || { echo "No disks detected." >&2; exit 1; }
  for e in "${disks[@]}"; do echo "  $e" >&2; done
  local choice; choice=$(ask "Choose a disk" "${disks[0]%% *}")
  [[ -b "/dev/$choice" ]] || { echo "Invalid disk." >&2; exit 1; }
  echo "/dev/$choice"
}

select_timezone() {
  local root=/usr/share/zoneinfo region city
  region=$(ask "Continent" "America" >&2; true)
  region=$(ask "Continent" "America")
  region=$(find "$root" -maxdepth 1 -iname "$region" -printf '%f' | head -n1)
  [[ -d "$root/$region" ]] || { echo "Invalid continent." >&2; exit 1; }
  echo "Cities in $region:" >&2
  ls "$root/$region" >&2
  city=$(ask "City" "$(ls "$root/$region" | shuf -n1)")
  city=$(find "$root/$region" -maxdepth 1 -iname "$city" -printf '%f' | head -n1)
  [[ -f "$root/$region/$city" ]] || { echo "Invalid city." >&2; exit 1; }
  echo "$region/$city"
}

read_password() {
  local label="$1" p1 p2
  while true; do
    read -rsp "$label: " p1; echo >&2
    read -rsp "Confirm $label: " p2; echo >&2
    [[ -n "$p1" && "$p1" == "$p2" ]] && break || echo "Mismatch, try again." >&2
  done
  echo "$p1"
}

partition_sizes() {
  local disk="$1" name gb
  name=$(basename "$disk")
  gb=$(( $(< "/sys/block/$name/size") * $(< "/sys/block/$name/queue/hw_sector_size") / 1024**3 ))
  if   ((gb < 20));  then echo "0.5 4"
  elif ((gb < 40));  then echo "1 8"
  elif ((gb < 100)); then echo "1 20"
  else                    echo "1 30"
  fi
}

partition_disk() {
  local disk="$1" fw="$2" boot_size="$3" root_size="$4"
  for p in $(lsblk -ln -o NAME "$disk" | tail -n +2); do
    mountpoint -q "/dev/$p" 2>/dev/null && umount "/dev/$p"
  done
  if [[ "$fw" == UEFI ]]; then
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
  udevadm settle; sleep 2
}

partition_paths() {
  local disk="$1" prefix=""
  [[ "$disk" =~ (nvme|mmcblk) ]] && prefix="p"
  echo "${disk}${prefix}1 ${disk}${prefix}2 ${disk}${prefix}3"
}

wait_for_partitions() {
  local tries=30
  for p in "$@"; do
    until [[ -b "$p" || $tries -eq 0 ]]; do sleep 1; ((tries--)); done
    [[ -b "$p" ]] || { echo "Partition $p never appeared." >&2; exit 1; }
  done
}

format_partitions() {
  local fw="$1" boot="$2" root="$3" home="$4"
  if [[ "$fw" == UEFI ]]; then mkfs.fat -F32 "$boot"; else mkfs.ext4 -F "$boot"; fi
  mkfs.ext4 -F "$root"
  mkfs.ext4 -F "$home"
}

mount_partitions() {
  local boot="$1" root="$2" home="$3"
  mount "$root" /mnt
  mkdir -p /mnt/boot /mnt/home
  mount "$boot" /mnt/boot
  mount "$home" /mnt/home
}

install_base() {
  local fw="$1"
  local pkgs=(base base-devel runit elogind-runit linux linux-firmware neovim networkmanager networkmanager-runit grub)
  [[ "$fw" == UEFI ]] && pkgs+=(efibootmgr)
  basestrap /mnt "${pkgs[@]}"
  fstabgen -U /mnt >> /mnt/etc/fstab
}

configure_system() {
  local fw="$1" tz="$2" hostname="$3" username="$4" disk="$5" rootpass="$6" userpass="$7"
  artix-chroot /mnt /bin/bash <<EOF
set -e
ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime
hwclock --systohc
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$hostname" > /etc/hostname
cat >> /etc/hosts <<HOSTS
127.0.0.1 localhost
::1 localhost
127.0.1.1 $hostname.localdomain $hostname
HOSTS
useradd -m -G wheel "$username"
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
ln -sf /etc/runit/sv/NetworkManager /etc/runit/runsvdir/default/NetworkManager
if [[ "$fw" == UEFI ]]; then
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
  grub-install --target=i386-pc "$disk"
fi
grub-mkconfig -o /boot/grub/grub.cfg
echo "root:$rootpass" | chpasswd
echo "$username:$userpass" | chpasswd
history -c
EOF
}

main() {
  check_root
  local fw hostname username rootpass userpass disk tz sizes boot_size root_size
  local boot_part root_part home_part

  fw=$(detect_firmware)
  echo "DarkArtix Installer v0.1"
  echo "Firmware: $fw"

  msg "Choosing a disk"
  disk=$(select_disk)
  confirm "This will erase all data on $disk. Continue?"

  msg "Setting the region"
  tz=$(select_timezone)

  msg "Hostname and username"
  hostname=$(ask "Hostname" "artix")
  username=$(ask "Username" "user")

  msg "Passwords"
  rootpass=$(read_password "Root password")
  userpass=$(read_password "Password for $username")

  read -r boot_size root_size <<< "$(partition_sizes "$disk" "$fw")"
  partition_disk "$disk" "$fw" "$boot_size" "$root_size"

  read -r boot_part root_part home_part <<< "$(partition_paths "$disk")"
  wait_for_partitions "$boot_part" "$root_part" "$home_part"

  format_partitions "$fw" "$boot_part" "$root_part" "$home_part"
  mount_partitions "$boot_part" "$root_part" "$home_part"

  install_base "$fw"
  configure_system "$fw" "$tz" "$hostname" "$username" "$disk" "$rootpass" "$userpass"

  unset rootpass userpass
  msg "Installation complete. Please reboot and remove the installation media."
}

main "$@"
