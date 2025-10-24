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

while true; do
  echo "Available continents:"
  echo "Africa  America  Antarctica  Asia  Atlantic  Australia  Europe  Mexico  Pacific  US"

  continent=$(default_prompt "Continent" "America")
  continent="$(tr '[:upper:]' '[:lower:]' <<< "$continent")"
  continent="$(tr '[:lower:]' '[:upper:]' <<< "${continent:0:1}")${continent:1}"

  # Check if continent exists
  if [[ ! -d "/usr/share/zoneinfo/$continent" ]]; then
    echo "Invalid option."
    echo
    continue
  fi

  timezone_base="/usr/share/zoneinfo/$continent"

  while true; do
    echo
    echo "Available cities in $continent:"
    ls "$timezone_base"

    cities=($(ls "$timezone_base"))
    default_city="${cities[RANDOM % ${#cities[@]}]}"

    city=$(default_prompt "City/Timezone" "$default_city")
    timezone="$timezone_base/$city"

    if [[ -d "$timezone" ]]; then
      # If user picked a subdirectory, drill down
      timezone_base="$timezone"
      continent="${continent}/$city"
      continue
    elif [[ ! -f "$timezone" ]]; then
      echo "Invalid option."
      echo
      continue
    fi

    message blue "Selected timezone: ${timezone#/usr/share/zoneinfo/}"
    break 2  # break out of both loops
  done
done
