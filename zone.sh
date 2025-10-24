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
echo "Available continents:"
echo "Africa  America  Antarctica  Asia  Atlantic  Australia  Europe  Mexico  Pacific  US"

continent=$(default_prompt "Continent" "America")
continent="$(tr '[:upper:]' '[:lower:]' <<< "$continent")"
continent="$(tr '[:lower:]' '[:upper:]' <<< "${continent:0:1}")${continent:1}"

echo
echo "Available cities in $continent:"
ls /usr/share/zoneinfo/"$continent"

cities=($(ls /usr/share/zoneinfo/"$continent"))
default_city="${cities[RANDOM % ${#cities[@]}]}"

city=$(default_prompt "City/Timezone" "$default_city")

timezone="$continent/$city"
message blue "Selected timezone: $timezone"

confirmation "Apply timezone setting?" "yes"

ln -sf /usr/share/zoneinfo/"$timezone" /etc/localtime
message green "Timezone set to $timezone"
