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

message blue "Timezone configuration"
zone_root="/usr/share/zoneinfo"

regions=(Africa America Antarctica Asia Atlantic Australia Europe Mexico Pacific US)
echo "Regions: ${regions[*]}"

while :; do
  region="$(tr '[:upper:]' '[:lower:]' <<< "$(default_prompt 'Region' 'America')")"
  region="${region^}"
  [[ -d "$zone_root/$region" || -d "$zone_root/${region^^}" ]] || { echo "Invalid region."; continue; }

  region_path="$zone_root/${region^^}"
  [[ -d "$zone_root/$region" ]] && region_path="$zone_root/$region"
  cities=($(ls "$region_path"))

  echo "Cities in $region:"
  printf '%s\n' "${cities[@]}"
  city="$(default_prompt 'City/Timezone' "${cities[RANDOM % ${#cities[@]}]}")"
  [[ ! " ${cities[*]} " =~ " ${city} " ]] && { echo "Invalid city."; continue; }

  timezone="$region/$city"
  message yellow "Selected timezone: $timezone"
  confirmation "Apply this timezone?" "yes" || { message yellow "Canceled. Try again."; continue; }

  sudo ln -sf "$zone_root/$timezone" /etc/localtime
  echo "$timezone" | sudo tee /etc/timezone >/dev/null
  message green "Timezone set to $timezone"
  break
