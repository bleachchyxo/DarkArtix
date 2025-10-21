#!/bin/bash
set -euo pipefail

# Root check
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root."
  exit 1
fi

# Detect firmware
if [ -d /sys/firmware/efi ]; then
  firmware="UEFI"
else
  firmware="BIOS"
fi

# notification system
message() {
  local color="$1"
  local msg="$2"
  case "$color" in
    green) echo -e "\033[32m[+]\033[0m $msg" ;;
    yellow) echo -e "\033[33m[+]\033[0m $msg" ;;
    blue) echo -e "\033[34m[+]\033[0m $msg" ;;
    *) echo "[+] $msg" ;;
  esac
}

default_prompt() {
  local prompt="$1"
  local default="$2"
  read -rp "$prompt [$default]: " input
  echo "${input:-$default}"
}

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

# Choosing a disk
message blue "Choosing a disk"
mapfile -t disks < <(lsblk -dno NAME,SIZE,TYPE | awk '$3 == "disk" && $1 !~ /loop/ && $1 !~ /ram/ {print $1, $2}')
for disk_entry in "${disks[@]}"; do
  echo "  $disk_entry"
done

default_disk="${disks[0]%% *}"
disk_name=$(default_prompt "Choose a disk to install" "$default_disk")
disk="/dev/$disk_name"

if [[ ! -b "$disk" ]]; then
  echo "Invalid disk: $disk"
  exit 1
fi
confirmation "This will erase all data on $disk. Continue?" "no"

# Choosing a username
message blue "Setting hostname and username"
hostname=$(default_prompt "hostname" "artix")
username=$(default_prompt "username" "user")

# Timezone selection
print_message "Available continents:"
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
if [[ -z "$continent_matched" ]]; then
  echo "Invalid continent '$continent_input'. Please try again."
  exit 1
fi

# Pick cities based on continent
print_message "Available cities in $continent_matched:"
mapfile -t cities < <(find "/usr/share/zoneinfo/$continent_matched" -type f -exec basename {} \; | sort)

cols=4
for i in "${!cities[@]}"; do
  if (( i % cols == 0 )); then
    echo
  fi
  printf "%-15s" "${cities[$i]}"
done
echo

city_input=$(ask "City" "${cities[0]}")
city=$(echo "$city_input" | awk '{print tolower($0)}')
city_matched=""
for c in "${cities[@]}"; do
  if [[ "${c,,}" == "$city" ]]; then
    city_matched="$c"
    break
  fi
done
if [[ -z "$city_matched" ]]; then
  echo "Invalid city '$city_input'. Please try again."
  exit 1
fi
timezone="$continent_matched/$city_matched"


