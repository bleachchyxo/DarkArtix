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

message blue "Choose a continent;"
echo "Africa  America  Antarctica  Asia  Atlantic  Australia  Europe  Pacific"

continent=$(default_prompt "Continent" "America")
continent="$(tr '[:upper:]' '[:lower:]' <<< "$continent")"
continent="$(tr '[:lower:]' '[:upper:]' <<< "${continent:0:1}")${continent:1}"

echo
message blue "Choose a timezone in $continent;"
ls /usr/share/zoneinfo/"$continent"

city=$(default_prompt "City/Timezone" "New_York")

timezone="$continent/$city"
message blue "Selected timezone: $timezone"

confirmation "Apply timezone setting?" "yes"

ln -sf /usr/share/zoneinfo/"$timezone" /etc/localtime
message green "Timezone set to $timezone"
