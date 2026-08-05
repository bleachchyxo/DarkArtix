#!/bin/bash
set -euo pipefail

print_step()      { echo -e "\033[32m[+]\033[0m $1"; }
prompt_default()  { read -rp "$1 [$2]: " answer; echo "${answer:-$2}"; }
confirm_or_exit() { read -rp "$1 [y/N]: " answer; [[ "${answer,,}" =~ ^y ]] || { echo "Aborted."; exit 1; }; }

ensure_running_as_root() { [[ $EUID -eq 0 ]] || { echo "Please run as root."; exit 1; }; }
detect_firmware()        { [[ -d /sys/firmware/efi ]] && echo UEFI || echo BIOS; }

select_disk() {
  echo "Available disks:" >&2
  mapfile -t available_disks < <(lsblk -dno NAME,SIZE,TYPE | awk '$3=="disk" && $1!~/loop|ram/ {print $1, $2}')
  ((${#available_disks[@]})) || { echo "No disks detected." >&2; exit 1; }

  local max_name_length=0 max_size_length=0
  for disk_entry in "${available_disks[@]}"; do
    local disk_name="${disk_entry%% *}" disk_size="${disk_entry#* }"
    (( ${#disk_name} > max_name_length )) && max_name_length=${#disk_name}
    (( ${#disk_size} > max_size_length )) && max_size_length=${#disk_size}
  done

  for disk_entry in "${available_disks[@]}"; do
    local disk_name="${disk_entry%% *}" disk_size="${disk_entry#* }"
    local disk_path="/dev/$disk_name"
    local partition_type disk_model
    partition_type=$(lsblk -dn -o PTTYPE "$disk_path")
    disk_model=$(fdisk -l "$disk_path" 2>/dev/null | awk -F: '/Disk model/ {gsub(/^ +/,"",$2); print $2}')
    printf "  %-${max_name_length}s  %-${max_size_length}s (%s)\n" \
      "$disk_name" "$disk_size" "${disk_model:-$partition_type}" >&2
  done

  local disk_name; disk_name=$(prompt_default "Choose a disk" "${available_disks[0]%% *}")
  [[ -b "/dev/$disk_name" ]] || { echo "Invalid disk." >&2; exit 1; }
  echo "/dev/$disk_name"
}

# finds a subdirectory of $1 matching $2 case-insensitively, or exits
find_matching_subdirectory() {
  local matched_name; matched_name=$(find "$1" -maxdepth 1 -iname "$2" -printf '%f' | head -n1)
  [[ -n "$matched_name" ]] || { echo "Invalid option: $2" >&2; exit 1; }
  echo "$matched_name"
}

select_timezone() {
  local zoneinfo_root=/usr/share/zoneinfo continent city
  echo "Available continents:" >&2
  echo "Africa  America  Antarctica  Asia  Atlantic  Australia  Europe  Mexico  Pacific  US" >&2
  continent=$(find_matching_subdirectory "$zoneinfo_root" "$(prompt_default "Continent" "America")")
  ls "$zoneinfo_root/$continent" >&2
  city=$(find_matching_subdirectory "$zoneinfo_root/$continent" "$(prompt_default "City" "$(ls "$zoneinfo_root/$continent" | shuf -n1)")")
  echo "$continent/$city"
}

read_confirmed_password() {
  local label="$1" password password_confirmation
  while true; do
    read -rsp "$label: " password; echo >&2
    read -rsp "Confirm $label: " password_confirmation; echo >&2
    [[ -n "$password" && "$password" == "$password_confirmation" ]] && break || echo "Mismatch, try again." >&2
  done
  echo "$password"
}

# partitions, formats and mounts $1=disk $2=firmware; sets BOOT_PARTITION/ROOT_PARTITION/HOME_PARTITION
prepare_disk_partitions() {
  local disk="$1" firmware="$2" disk_basename disk_size_gb boot_size root_size partition_prefix=""
  disk_basename=$(basename "$disk")
  disk_size_gb=$(( $(< "/sys/block/$disk_basename/size") * $(< "/sys/block/$disk_basename/queue/hw_sector_size") / 1024**3 ))
  if   ((disk_size_gb < 20));  then boot_size=0.5 root_size=4
  elif ((disk_size_gb < 40));  then boot_size=1   root_size=8
  elif ((disk_size_gb < 100)); then boot_size=1   root_size=20
  else                              boot_size=1   root_size=30
  fi

  for partition_name in $(lsblk -ln -o NAME "$disk" | tail -n +2); do
    mountpoint -q "/dev/$partition_name" 2>/dev/null && umount "/dev/$partition_name"
  done

  if [[ "$firmware" == UEFI ]]; then
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

  [[ "$disk" =~ (nvme|mmcblk) ]] && partition_prefix="p"
  BOOT_PARTITION="${disk}${partition_prefix}1"
  ROOT_PARTITION="${disk}${partition_prefix}2"
  HOME_PARTITION="${disk}${partition_prefix}3"

  local attempts_remaining=30
  for partition_path in "$BOOT_PARTITION" "$ROOT_PARTITION" "$HOME_PARTITION"; do
    until [[ -b "$partition_path" || $attempts_remaining -eq 0 ]]; do
      sleep 1; ((attempts_remaining--))
    done
    [[ -b "$partition_path" ]] || { echo "Partition $partition_path never appeared." >&2; exit 1; }
  done

  if [[ "$firmware" == UEFI ]]; then mkfs.fat -F32 "$BOOT_PARTITION"; else mkfs.ext4 -F "$BOOT_PARTITION"; fi
  mkfs.ext4 -F "$ROOT_PARTITION"
  mkfs.ext4 -F "$HOME_PARTITION"

  mount "$ROOT_PARTITION" /mnt
  mkdir -p /mnt/boot /mnt/home
  mount "$BOOT_PARTITION" /mnt/boot
  mount "$HOME_PARTITION" /mnt/home
}

install_base_packages() {
  local firmware="$1"
  local packages=(base base-devel runit elogind-runit linux linux-firmware neovim networkmanager networkmanager-runit grub)
  [[ "$firmware" == UEFI ]] && packages+=(efibootmgr)
  basestrap /mnt "${packages[@]}"
  fstabgen -U /mnt >> /mnt/etc/fstab
}

configure_system() {
  local firmware="$1" timezone="$2" hostname="$3" username="$4" disk="$5" root_password="$6" user_password="$7"
  artix-chroot /mnt /bin/bash <<EOF
set -e
ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime
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
if [[ "$firmware" == UEFI ]]; then
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
  grub-install --target=i386-pc "$disk"
fi
grub-mkconfig -o /boot/grub/grub.cfg
echo "root:$root_password" | chpasswd
echo "$username:$user_password" | chpasswd
history -c
EOF
}

main() {
  ensure_running_as_root
  local firmware disk timezone hostname username root_password user_password

  firmware=$(detect_firmware)
  echo "DarkArtix Installer v0.1"
  echo "Firmware: $firmware"

  print_step "Choosing a disk"
  disk=$(select_disk)
  confirm_or_exit "This will erase all data on $disk. Continue?"

  print_step "Setting the region"
  timezone=$(select_timezone)

  print_step "Hostname and username"
  hostname=$(prompt_default "Hostname" "artix")
  username=$(prompt_default "Username" "user")

  print_step "Passwords"
  root_password=$(read_confirmed_password "Root password")
  user_password=$(read_confirmed_password "Password for $username")

  prepare_disk_partitions "$disk" "$firmware"
  install_base_packages "$firmware"
  configure_system "$firmware" "$timezone" "$hostname" "$username" "$disk" "$root_password" "$user_password"

  unset root_password user_password
  print_step "Installation complete. Please reboot and remove the installation media."
}

main "$@"
