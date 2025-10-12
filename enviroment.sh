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

echo "Patching config files..."

# dmenu: set topbar to 0
sed -i 's/static int topbar = 1;/static int topbar = 0;/' "$config_directory/dmenu/config.def.h"
rm -f "$config_directory/dmenu/config.h"

# dwm: set topbar to 0
sed -i 's/static const int topbar\s*= 1;/static const int topbar = 0;/' "$config_directory/dwm/config.def.h"
rm -f "$config_directory/dwm/config.h"

# st: font size and keybindings
st_config="$config_directory/st/config.def.h"
sed -i 's/pixelsize=12/pixelsize=27/' "$st_config"
sed -i 's/{ TERMMOD, *XK_Prior, *zoom, *{.f = +1} }/{ TERMMOD, XK_K, zoom, {.f = +1} }/' "$st_config"
sed -i 's/{ TERMMOD, *XK_Next, *zoom, *{.f = -1} }/{ TERMMOD, XK_J, zoom, {.f = -1} }/' "$st_config"
rm -f "$config_directory/st/config.h"

for program in dwm dmenu st; do
  echo "Building and installing $program..."
  make -C "$config_directory/$program" clean
  make -C "$config_directory/$program" install
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
