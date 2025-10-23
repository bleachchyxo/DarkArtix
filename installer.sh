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

continent_input=$(default_prompt "Continent" "America")
continent_lower=$(echo "$continent_input" | awk '{print tolower($0)}')

# Match user input to a valid continent name (case-insensitive)
selected_continent=""
for cont in "${continents_list[@]}"; do
  if [[ "${cont,,}" == "$continent_lower" ]]; then
    selected_continent="$cont"
    break
  fi
done

if [[ -z "$selected_continent" ]]; then
  echo "Invalid continent '$continent_input'. Please try again."
  exit 1
fi

# Now list countries inside the selected continent (these are directories)
echo "Available countries in $selected_continent:"
mapfile -t countries_list < <(find "/usr/share/zoneinfo/$selected_continent" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)

if [[ ${#countries_list[@]} -eq 0 ]]; then
  echo "No countries found in continent $selected_continent."
  exit 1
fi

# Display countries in columns with 14 rows per column
rows_per_column=14
total_countries=${#countries_list[@]}
columns_needed=$(( (total_countries + rows_per_column - 1) / rows_per_column ))

for (( row=0; row < rows_per_column; row++ )); do
  for (( col=0; col < columns_needed; col++ )); do
    idx=$(( col * rows_per_column + row ))
    if (( idx >= total_countries )); then
      if (( col == columns_needed -1 )); then
        break
      else
        printf "%-20s" ""
        continue
      fi
    fi
    printf "%-20s" "${countries_list[$idx]}"
  done
  echo
done

# Prompt for country selection
country_input=$(default_prompt "Country" "${countries_list[0]}")
country_lower=$(echo "$country_input" | awk '{print tolower($0)}')

selected_country=""
for country in "${countries_list[@]}"; do
  if [[ "${country,,}" == "$country_lower" ]]; then
    selected_country="$country"
    break
  fi
done

if [[ -z "$selected_country" ]]; then
  echo "Invalid country '$country_input'. Please try again."
  exit 1
fi

# List cities inside the selected country (files in directory)
echo "Available cities in $selected_country:"
mapfile -t cities_list < <(find "/usr/share/zoneinfo/$selected_continent/$selected_country" -type f -exec basename {} \; | sort)

if [[ ${#cities_list[@]} -eq 0 ]]; then
  echo "No cities found in country $selected_country."
  exit 1
fi

# Display cities in columns with 14 rows per column
total_cities=${#cities_list[@]}
columns_needed=$(( (total_cities + rows_per_column - 1) / rows_per_column ))

for (( row=0; row < rows_per_column; row++ )); do
  for (( col=0; col < columns_needed; col++ )); do
    idx=$(( col * rows_per_column + row ))
    if (( idx >= total_cities )); then
      if (( col == columns_needed -1 )); then
        break
      else
        printf "%-20s" ""
        continue
      fi
    fi
    printf "%-20s" "${cities_list[$idx]}"
  done
  echo
done

# Prompt for city selection
city_input=$(default_prompt "City" "${cities_list[0]}")
city_lower=$(echo "$city_input" | awk '{print tolower($0)}')

selected_city=""
for city in "${cities_list[@]}"; do
  if [[ "${city,,}" == "$city_lower" ]]; then
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
