#!/bin/bash
set -euo pipefail

# Ensure script is run with sudo
if [[ -z "${SUDO_USER:-}" ]]; then
  echo "This script must be run with sudo."
  exit 1
fi

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

# Update system and installing packages
pacman -Syyu --noconfirm
pacman -S --noconfirm \
  gcc make git \
  libx11 libxinerama libxft \
  xorg xorg-xinit \
  ttf-dejavu ttf-font-awesome \
  alsa-utils-runit \
  xcompmgr

# .config 
mkdir -p "$HOME/.config"

# cloning suckless repos
for repository in dwm dmenu st; do
  git -C "$HOME/.config" clone --depth 1 "https://git.suckless.org/$repository" "$HOME/.config/$repository"
done

chown -R "$USER:$USER" "$HOME/.config"
