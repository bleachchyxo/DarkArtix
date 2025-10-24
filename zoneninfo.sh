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

timezone_root_directory="/usr/share/zoneinfo"

while true; do
  echo "Available regions:"
  echo "Africa  America  Antarctica  Asia  Atlantic  Australia  Europe  Mexico  Pacific  US"

  selected_region="$(tr '[:upper:]' '[:lower:]' <<< "$(default_prompt "Region" "America")")"
  selected_region="${selected_region^}"

  [[ -d "$timezone_root_directory/$selected_region" || -d "$timezone_root_directory/${selected_region^^}" ]] || { 
    echo "Invalid option."; 
    continue; 
  }

  selected_region=$( [[ -d "$timezone_root_directory/$selected_region" ]] && echo "$selected_region" || echo "${selected_region^^}" )
  current_timezone_path="$timezone_root_directory/$selected_region"
  selected_timezone_path="$selected_region"

  while true; do
    echo "Available timezones in $selected_timezone_path:"
    ls "$current_timezone_path"
    available_timezones=($(ls "$current_timezone_path"))
    user_timezone_input=$(default_prompt "City/Timezone" "${available_timezones[RANDOM % ${#available_timezones[@]}]}")

    matched_timezone_entry=""
    for timezone_option in "${available_timezones[@]}"; do
      [[ "${timezone_option,,}" == "${user_timezone_input,,}" ]] && matched_timezone_entry="$timezone_option" && break
    done

    [[ -z "$matched_timezone_entry" ]] && { echo "Invalid option."; continue; }

    current_timezone_path="$current_timezone_path/$matched_timezone_entry"
    selected_timezone_path="$selected_timezone_path/$matched_timezone_entry"
    
  done
done
