#!/bin/bash
set -euo pipefail

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root."
  exit 1
fi

# Detect if system booted in UEFI or BIOS mode
if [ -d /sys/firmware/efi ]; then
  firmware="UEFI"
else
  firmware="BIOS"
fi

# Function to print colored messages
message() {
  local color="$1"
  local msg="$2"
  case "$color" in
    green)  echo -e "\033[32m[+]\033[0m $msg" ;;
    yellow) echo -e "\033[33m[+]\033[0m $msg" ;;
    blue)   echo -e "\033[34m[+]\033[0m $msg" ;;
    *)      echo "[+] $msg" ;;
  esac
}

# Prompt with default value
default_prompt() {
  local prompt="$1"
  local default="$2"
  read -rp "$prompt [$default]: " input
  echo "${input:-$default}"
}

# Yes/No confirmation prompt with default answer
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

# List available disks for installation
message blue "Choosing a disk"
mapfile -t available_disks < <(lsblk -dno NAME,SIZE,TYPE | awk '$3 == "disk" && $1 !~ /loop/ && $1 !~ /ram/ {print $1, $2}')

if [[ ${#available_disks[@]} -eq 0 ]]; then
  echo "No disks detected."
  exit 1
fi

# Show disks with sizes
for disk_entry in "${available_disks[@]}"; do
  echo "  $disk_entry"
done

default_disk="${available_disks[0]%% *}"
disk_choice=$(default_prompt "Choose a disk to install" "$default_disk")
disk="/dev/$disk_choice"

# Validate disk choice
if [[ -z "${disk_choice:-}" || ! -b "$disk" ]]; then
  echo "Invalid or missing disk selection."
  exit 1
fi

confirmation "This will erase all data on $disk. Continue?" "no"

# Prompt for hostname and username
message blue "Setting hostname and username"
hostname=$(default_prompt "Hostname" "artix")
username=$(default_prompt "Username" "user")

# Timezone selection
message blue "Timezone selection"
echo "Available continents:"

# List valid continents (directories under /usr/share/zoneinfo)
mapfile -t continents_list < <(find /usr/share/zoneinfo -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | \
  grep -E '^(Africa|America|Antarctica|Arctic|Asia|Atlantic|Australia|Europe|Indian|Pacific)$' | sort)

echo "  ${continents_list[@]}"

# Continent selection
continent_input=$(default_prompt "Continent" "America")

selected_continent=""
for cont in "${continents_list[@]}"; do
  if [[ "$cont" == "$continent_input" ]]; then
    selected_continent="$cont"
    break
  fi
done

if [[ -z "$selected_continent" ]]; then
  echo "Invalid continent '$continent_input'. Please try again."
  exit 1
fi

# Country selection
# Continent selection
continent_input=$(default_prompt "Continent" "America")

selected_continent=""
for cont in "${continents_list[@]}"; do
  if [[ "$cont" == "$continent_input" ]]; then
    selected_continent="$cont"
    break
  fi
done

if [[ -z "$selected_continent" ]]; then
  echo "Invalid continent '$continent_input'. Please try again."
  exit 1
fi

# Country selection
country_input=$(default_prompt "Country" "${countries_list[0]}")

selected_country=""
for country in "${countries_list[@]}"; do
  if [[ "$country" == "$country_input" ]]; then
    selected_country="$country"
    break
  fi
done

if [[ -z "$selected_country" ]]; then
  echo "Invalid country '$country_input'. Please try again."
  exit 1
fi

# City selection
city_input=$(default_prompt "City" "${cities_list[0]}")

selected_city=""
for city in "${cities_list[@]}"; do
  if [[ "$city" == "$city_input" ]]; then
    selected_city="$city"
    break
  fi
done

if [[ -z "$selected_city" ]]; then
  echo "Invalid city '$city_input'. Please try again."
  exit 1
fi

timezone="$selected_continent/$selected_country/$selected_city"
echo "Selected timezone: $timezone"
