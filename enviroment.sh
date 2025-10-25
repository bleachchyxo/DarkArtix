#!/bin/bash
set -euo pipefail

# Ensure script is run with sudo
if [[ -z "${SUDO_USER:-}" ]]; then
  echo "This script must be run with sudo."
  exit 1
fi

user_home="/home/$SUDO_USER"
config_directory="$user_home/.config"
xinitrc_path="$user_home/.xinitrc"
bash_profile_path="$user_home/.bash_profile"
alsa_service_link="/etc/runit/runsvdir/default/alsa"

echo "Updating package list and system..."
pacman -Syyu --noconfirm

echo "Installing required packages..."
pacman -S --noconfirm \
  gcc make git \
  libx11 libxinerama libxft \
  xorg xorg-xinit \
  ttf-dejavu ttf-font-awesome \
  alsa-utils-runit

echo "Creating configuration directory at $config_directory..."
mkdir -p "$config_directory"
cd "$config_directory"

for repository in dwm dmenu st; do
  if [[ ! -d "$repository" ]]; then
    echo "Cloning $repository..."
    git clone "https://git.suckless.org/$repository"
  else
    echo "$repository already cloned, skipping."
  fi
done

dwm_config="${config_directory}/dwm/config.def.h"
if grep -q '#define MODKEY Mod1Mask' "$dwm_config"; then
  echo "Patching dwm to use Mod4 (Super) as MODKEY..."
  sed -i 's/#define MODKEY Mod1Mask/#define MODKEY Mod4Mask/' "$dwm_config"
  rm -f "${config_directory}/dwm/config.h"
fi

for program in dwm dmenu st; do
  echo "Building and installing $program..."
  make -C "${config_directory}/${program}" clean
  make -C "${config_directory}/${program}" install
done

echo "Creating .xinitrc to launch dwm..."
echo "exec dwm" > "$xinitrc_path"
chown "$SUDO_USER:$SUDO_USER" "$xinitrc_path"

echo "Creating .bash_profile to auto-start X on tty1..."
cat > "$bash_profile_path" <<'EOF'
if [[ -z $DISPLAY ]] && [[ $(tty) = /dev/tty1 ]]; then
    startx
fi
EOF
chown "$SUDO_USER:$SUDO_USER" "$bash_profile_path"

if [[ ! -L "$alsa_service_link" ]]; then
  echo "Enabling ALSA service with runit..."
  ln -s /etc/runit/sv/alsa "$alsa_service_link"
fi

echo
echo "Suckless environment setup complete. Log in on tty1 to start dwm."
