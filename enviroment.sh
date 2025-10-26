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

# dmenu
sed -i 's/static int topbar = 1;/static int topbar = 0;/' $HOME/.config/dmenu/config.def.h
make -C $HOME/.config/dmenu install

# dwm
curl -s -o $HOME/.config/dwm/dwm-fullgaps-20200508-7b77734.diff https://dwm.suckless.org/patches/fullgaps/dwm-fullgaps-20200508-7b77734.diff
patch -d $HOME/.config/dwm < $HOME/.config/dwm/dwm-fullgaps-20200508-7b77734.diff
sed -i 's/static const unsigned int gappx     = 5;/static const unsigned int gappx     = 15;/' $HOME/.config/dwm/config.def.h
sed -i '8s/topbar\s*=\s*1;/topbar = 0;/g' $HOME/.config/dwm/config.def.h
sed -i 's/#define MODKEY Mod1Mask/#define MODKEY Mod4Mask/' $HOME/.config/dwm/config.def.h
make -C $HOME/.config/dwm install
rm $HOME/.config/dwm/dwm-fullgaps-20200508-7b77734.diff
rm $HOME/.config/dwm/*.orig

# st
curl -s -o $HOME/.config/st/st-alpha-20240814-a0274bc.diff https://st.suckless.org/patches/alpha/st-alpha-20240814-a0274bc.diff
patch -d $HOME/.config/st < $HOME/.config/st/st-alpha-20240814-a0274bc.diff
curl -s -o $HOME/.config/st/st-blinking_cursor-20230819-3a6d6d7.diff https://st.suckless.org/patches/blinking_cursor/st-blinking_cursor-20230819-3a6d6d7.diff
patch -d $HOME/.config/st < $HOME/.config/st/st-blinking_cursor-20230819-3a6d6d7.diff
