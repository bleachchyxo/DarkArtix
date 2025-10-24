#!/usr/bin/env bash

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

message blue "Setting the timezone"

zone_root="/usr/share/zoneinfo"

while true; do
  echo "Available continents:"
  echo "Africa  America  Antarctica  Asia  Atlantic  Australia  Europe  Mexico  Pacific  US"
  region="$(tr '[:upper:]' '[:lower:]' <<< "$(default_prompt "Continent" "America")")"
  region="${region^}"
  [[ -d "$zone_root/$region" || -d "$zone_root/${region^^}" ]] || { echo "Invalid option."; continue; }
  region=$( [[ -d "$zone_root/$region" ]] && echo "$region" || echo "${region^^}" )

  region_path="$zone_root/$region"
  timezone="$region"

  while true; do
    echo "Available cities in $timezone:"
    ls "$region_path"
    cities=($(ls "$region_path"))
    city=$(default_prompt "City/Timezone" "${cities[RANDOM % ${#cities[@]}]}")

    match=""
    for e in "${cities[@]}"; do [[ "${e,,}" == "${city,,}" ]] && match="$e" && break; done
    [[ -z "$match" ]] && { echo "Invalid option."; continue; }

    region_path="$region_path/$match"
    timezone="$timezone/$match"
    [[ -f "$region_path" ]] && { message blue "Selected timezone: $timezone"; break 2; }
  done
done
