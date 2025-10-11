#!/bin/bash
set -euo pipefail

# --- Check for root ---
if [[ $EUID -eq 0 ]]; then
  echo "Please run this script as a regular user, not root."
  exit 1
fi

# --- Update system ---
echo "Updating system..."
sudo pacman -Syyu --noconfirm

# --- Install compiler and dependencies ---
echo "Installing gcc and important libraries..."
sudo pacman -S --noconfirm gcc libx11 libxinerama libxft git xorg xorg-xinit ttf-dejavu ttf-font-awesome alsa-utils alsa-utils-runit

# --- Create config directory ---
CONFIG_DIR="$HOME/.config"
mkdir -p "$CONFIG_DIR"
cd "$CONFIG_DIR"

# --- Clone suckless repos ---
echo "Cloning suckless repositories..."
for repo in dwm dmenu st; do
  if [ -d "$repo" ]; then
    echo "$repo already exists, skipping clone."
  else
    git clone "https://git.suckless.org/$repo"
  fi
done

# --- Patch dwm config.def.h ---
DWM_CONFIG="$CONFIG_DIR/dwm/config.def.h"
if grep -q 'Mod1Mask' "$DWM_CONFIG"; then
  echo "Patching dwm config.def.h to change MODKEY to Mod4Mask..."
  sed -i 's/#define MODKEY Mod1Mask/#define MODKEY Mod4Mask/' "$DWM_CONFIG"
else
  echo "dwm config.def.h already patched or MODKEY not found."
fi

# --- Compile and install suckless tools ---
for tool in dwm dmenu st; do
  echo "Building and installing $tool..."
  (cd "$CONFIG_DIR/$tool" && make clean && sudo make install)
done

# --- Setup ~/.xinitrc ---
XINITRC="$HOME/.xinitrc"
if ! grep -q '^exec dwm' "$XINITRC" 2>/dev/null; then
  echo "Adding 'exec dwm' to $XINITRC..."
  echo "exec dwm" >> "$XINITRC"
else
  echo "$XINITRC already configured."
fi

# --- Enable ALSA service ---
echo "Enabling ALSA service with runit..."
if [ ! -L /etc/runit/runsvdir/default/alsa ]; then
  sudo ln -s /etc/runit/sv/alsa /etc/runit/runsvdir/default/
else
  echo "ALSA service link already exists."
fi

# --- Setup ~/.bash_profile to start X on tty1 ---
BASH_PROFILE="$HOME/.bash_profile"
STARTX_SNIPPET=$'if [[ -z $DISPLAY ]] && [[ $(tty) == /dev/tty1 ]]; then\n  startx\nfi\n'

if ! grep -q 'startx' "$BASH_PROFILE" 2>/dev/null; then
  echo "Adding automatic startx to $BASH_PROFILE..."
  echo -e "$STARTX_SNIPPET" >> "$BASH_PROFILE"
else
  echo "$BASH_PROFILE already contains startx snippet."
fi

echo
echo "Setup complete! Reboot or log out and log in on tty1 to start dwm."
