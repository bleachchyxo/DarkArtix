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

# Loop until valid continent and city are selected
while true; do
  echo "Available continents:"
  echo "Africa  America  Antarctica  Asia  Atlantic  Australia  Europe  Mexico  Pacific  US"

  continent=$(default_prompt "Continent" "America")

  # Normalize first letter capitalization for continent
  continent="$(tr '[:upper:]' '[:lower:]' <<< "$continent")"
  continent="$(tr '[:lower:]' '[:upper:]' <<< "${continent:0:1}")${continent:1}"

  if [[ ! -d "/usr/share/zoneinfo/$continent" && ! -d "/usr/share/zoneinfo/${continent^^}" ]]; then
      echo "Invalid option."
      continue
  fi

  # Then normalize to the actual directory name
  if [[ -d "/usr/share/zoneinfo/$continent" ]]; then
      continent="$continent"
  else
      continent="${continent^^}"
  fi

  timezone_base="/usr/share/zoneinfo/$continent"
  display_continent="$continent"

  # Loop for city selection (supports nested directories)
  while true; do
    echo "Available cities in $display_continent:"
    ls "$timezone_base"

    # List all entries (files and directories)
    entries=($(ls "$timezone_base"))
    default_entry="${entries[RANDOM % ${#entries[@]}]}"

    entry=$(default_prompt "City/Timezone" "$default_entry")

    # Case-insensitive match against entries
    match=""
    for e in "${entries[@]}"; do
      if [[ "${e,,}" == "${entry,,}" ]]; then
        match="$e"
        break
      fi
    done

    if [[ -z "$match" ]]; then
      echo "Invalid option."
      continue
    fi

    next_path="$timezone_base/$match"

    if [[ -d "$next_path" ]]; then
      # Drill down if it's a directory
      timezone_base="$next_path"
      display_continent="$display_continent/$match"
      continue
    elif [[ -f "$next_path" ]]; then
      timezone="$display_continent/$match"
      message blue "Selected timezone: $timezone"
      break 2  # Exit both loops
    else
      echo "Invalid option."
      continue
    fi
  done
done
