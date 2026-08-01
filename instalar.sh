#!/bin/bash
set -euo pipefail

msg()     { echo -e "\033[32m[+]\033[0m $1"; }
ask()     { read -rp "$1 [$2]: " r; echo "${r:-$2}"; }
confirm() { read -rp "$1 [y/N]: " a; [[ "${a,,}" =~ ^y ]] || { echo "Aborted."; exit 1; }; }

check_root()      { [[ $EUID -eq 0 ]] || { echo "Please run as root."; exit 1; }; }
detect_firmware() { [[ -d /sys/firmware/efi ]] && echo UEFI || echo BIOS; }

select_disk() {
  mapfile -t disks < <(lsblk -dno NAME,SIZE,TYPE | awk '$3=="disk" && $1!~/loop|ram/ {print $1, $2}')
  ((${#disks[@]})) || { echo "No disks detected." >&2; exit 1; }
  printf '  %s\n' "${disks[@]}" >&2
  local choice; choice=$(ask "Choose a disk" "${disks[0]%% *}")
  [[ -b "/dev/$choice" ]] || { echo "Invalid disk." >&2; exit 1; }
  echo "/dev/$choice"
}

# picks a subdir of $1 matching $2 case-insensitively, or exits
pick() {
  local match; match=$(find "$1" -maxdepth 1 -iname "$2" -printf '%f' | head -n1)
  [[ -n "$match" ]] || { echo "Invalid option: $2" >&2; exit 1; }
  echo "$match"
}

select_timezone() {
  local root=/usr/share/zoneinfo region city
  region=$(pick "$root" "$(ask "Continent" "America")")
  ls "$root/$region" >&2
  city=$(pick "$root/$region" "$(ask "City" "$(ls "$root/$region" | shuf -n1)")")
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

# partitions+formats+mounts $1=disk $2=firmware; sets BOOT_P/ROOT_P/HOME_P
prepare_disk() {
  local disk="$1" fw="$2" name gb boot_size root_size prefix=""
  name=$(basename "$disk")
  gb=$(( $(< "/sys/block/$name/size") * $(< "/sys/block/$name/queue/hw_sector_size") / 1024**3 ))
  if   ((gb < 20));  then boot_size=0.5 root_size=4
  elif ((gb < 40));  then boot_size=1   root_size=8
  elif ((gb < 100)); then boot_size=1   root_size=20
  else                    boot_size=1   root_size=30
  fi

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

  [[ "$disk" =~ (nvme|mmcblk) ]] && prefix="p"
  BOOT_P="${disk}${prefix}1"; ROOT_P="${disk}${prefix}2"; HOME_P="${disk}${prefix}3"

  local tries=30
  for p in "$BOOT_P" "$ROOT_P" "$HOME_P"; do
    until [[ -b "$p" || $tries -eq 0 ]]; do sleep 1; ((tries--)); done
    [[ -b "$p" ]] || { echo "Partition $p never appeared." >&2; exit 1; }
  done

  if [[ "$fw" == UEFI ]]; then mkfs.fat -F32 "$BOOT_P"; else mkfs.ext4 -F "$BOOT_P"; fi
  mkfs.ext4 -F "$ROOT_P"
  mkfs.ext4 -F "$HOME_P"

  mount "$ROOT_P" /mnt
  mkdir -p /mnt/boot /mnt/home
  mount "$BOOT_P" /mnt/boot
  mount "$HOME_P" /mnt/home
}

install_base() {
  local pkgs=(base base-devel runit elogind-runit linux linux-firmware neovim networkmanager networkmanager-runit grub)
  [[ "$1" == UEFI ]] && pkgs+=(efibootmgr)
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
  local fw disk tz hostname username rootpass userpass

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

  prepare_disk "$disk" "$fw"
  install_base "$fw"
  configure_system "$fw" "$tz" "$hostname" "$username" "$disk" "$rootpass" "$userpass"

  unset rootpass userpass
  msg "Installation complete. Please reboot and remove the installation media."
}

main "$@"
