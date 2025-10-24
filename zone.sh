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

normalize() { echo "${1^}"; }

pick_entry() {
  local path="$1" prompt="$2"
  entries=($(ls "$path"))
  echo "Available options in $path:"
  echo "${entries[*]}"
  entry=$(default_prompt "$prompt" "${entries[RANDOM % ${#entries[@]}]}")
  for e in "${entries[@]}"; do [[ "${e,,}" == "${entry,,}" ]] && echo "$e" && return; done
}

base="/usr/share/zoneinfo"
while true; do
  continent=$(normalize "$(default_prompt "Continent" "America")")
  [[ -d "$base/$continent" || -d "$base/${continent^^}" ]] || { echo "Invalid option."; continue; }
  continent=$( [[ -d "$base/$continent" ]] && echo "$continent" || echo "${continent^^}" )
  path="$base/$continent"
  display="$continent"

  while true; do
    match=$(pick_entry "$path" "City/Timezone")
    [[ -z "$match" ]] && { echo "Invalid option."; continue; }
    path="$path/$match"
    display="$display/$match"
    [[ -f "$path" ]] && { timezone="$display"; message blue "Selected timezone: $timezone"; break 2; }
  done
done
