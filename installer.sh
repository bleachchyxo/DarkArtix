#!/bin/bash
set -euo pipefail

# Root check
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root."
  exit 1
fi

# Detect firmware
if [ -d /sys/firmware/efi ]; then
  firmware="UEFI"
else
  firmware="BIOS"
fi

# notification system
message() {
    local color="$1"
    local msg="$2"
    
    case "$color" in
        green) echo -e "\033[32m[+]\033[0m $msg" ;;
        yellow) echo -e "\033[33m[+]\033[0m $msg" ;;
        blue) echo -e "\033[34m[+]\033[0m $msg" ;;
        *) echo "[+] $msg" ;; # Default case (no color for [+])
    esac
}

default_prompt() {
  local prompt="$1"
  local default="$2"
  read -rp "$prompt [$default]: " input
  echo "${input:-$default}"
}

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
message blue "Choosing a disk"
lsblk -dno NAME,SIZE,TYPE | awk '$3 == "disk" && $1 !~ /loop/ && $1 !~ /ram/ {print "  " $1, $2}'

