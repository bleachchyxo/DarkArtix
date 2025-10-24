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

list_options() { ls "$1"; }

normalize() { echo "${1^}"; }

pick_entry() {
  entries=($(list_options "$1"))
  entry=$(default_prompt "$2" "${entries[RANDOM % ${#entries[@]}]}")
  for e in "${entries[@]}"; do [[ "${e,,}" == "${entry,,}" ]] && echo "$e" && return; done
}

timezone_base="/usr/share/zoneinfo"
while true; do
  echo "Available continents:"
  echo "Africa  America  Antarctica  Asia  Atlantic  Australia  Europe  Mexico  Pacific  US"
  continent=$(normalize "$(default_prompt "Continent" "America")")
  [[ -d "$timezone_base/$continent" || -d "$timezone_base/${continent^^}" ]] || { echo "Invalid option."; continue; }
  continent=$( [[ -d "$timezone_base/$continent" ]] && echo "$continent" || echo "${continent^^}" )
  display="$continent"
  path="$timezone_base/$continent"

  while true; do
    echo "Available cities in $display:"
    match=$(pick_entry "$path" "City/Timezone")
    [[ -z "$match" ]] && { echo "Invalid option."; continue; }
    path="$path/$match"
    display="$display/$match"
    [[ -f "$path" ]] && { timezone="$display"; message blue "Selected timezone: $timezone"; break 2; }
  done
done
