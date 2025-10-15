#!/bin/bash
set -euo pipefail

# Must run as sudo
if [[ -z "${SUDO_USER:-}" ]]; then
  echo "This script must be run with sudo."
  exit 1
fi

user_home="/home/$SUDO_USER"
config_path="$user_home/.config"
xinitrc_file="$user_home/.xinitrc"
bash_profile_file="$user_home/.bash_profile"
alsa_service="/etc/runit/runsvdir/default/alsa"

echo "Updating package list and upgrading system..."
pacman -Syyu --noconfirm

echo "Installing essential packages..."
pacman -S --noconfirm \
  gcc make git \
  libx11 libxinerama libxft \
  xorg xorg-xinit \
  ttf-dejavu ttf-font-awesome \
  alsa-utils-runit xcompmgr

mkdir -p "$config_path"
cd "$config_path"

# Clone suckless repositories
for project in dwm dmenu st; do
  if [[ ! -d "$project" ]]; then
    echo "Cloning $project..."
    git clone "https://git.suckless.org/$project"
  else
    echo "$project already exists. Skipping clone."
  fi
done

chown -R "$SUDO_USER:$SUDO_USER" "$config_path"

# === ST PATCHING ===
cd "$config_path/st"

echo "Patching st: alpha..."
curl -LO https://st.suckless.org/patches/alpha/st-alpha-20240814-a0274bc.diff
patch < st-alpha-20240814-a0274bc.diff
rm -f st-alpha-20240814-a0274bc.diff config.h

echo "Patching st: blinking cursor..."
curl -LO https://st.suckless.org/patches/blinking_cursor/st-blinking_cursor-20230819-3a6d6d7.diff
patch < st-blinking_cursor-20230819-3a6d6d7.diff
rm -f st-blinking_cursor-20230819-3a6d6d7.diff config.def.h.orig config.h x.c.orig

echo "Configuring st font and shortcuts..."
sed -i 's/^static char \*font = .*/static char *font = "Liberation Mono:pixelsize=27:antialias=true:autohint=true";/' config.def.h
sed -i '/static Shortcut shortcuts\[\] = {/,/};/{
  s/{ TERMMOD, *XK_Prior, *zoom, *{.f = +1} },/{ TERMMOD,              XK_K,           zoom,           {.f = +1} },/
  s/{ TERMMOD, *XK_Next, *zoom, *{.f = -1} },/{ TERMMOD,              XK_J,           zoom,           {.f = -1} },/
}' config.def.h

# === DWM PATCHING ===
cd "$config_path/dwm"

echo "Patching dwm: fullgaps..."
curl -LO https://dwm.suckless.org/patches/fullgaps/dwm-fullgaps-20200508-7b77734.diff
patch < dwm-fullgaps-20200508-7b77734.diff
rm -f config.def.h.orig dwm.c.orig dwm-fullgaps-20200508-7b77734.diff config.h

echo "Adjusting gappx to 15px in dwm config..."
sed -i 's/^static const unsigned int gappx\s\+=\s\+5;/static const unsigned int gappx     = 15;/' config.def.h

# === MODKEY PATCHING (Super instead of Alt) ===
echo "Setting Mod4 (Super) as dwm MODKEY..."
sed -i 's/#define MODKEY Mod1Mask/#define MODKEY Mod4Mask/' config.def.h || true

# === BUILD AND INSTALL ===
for project in dwm dmenu st; do
  echo "Building and installing $project..."
  make -C "$config_path/$project" clean
  make -C "$config_path/$project" install
done

# === AUTOSTART ===
echo "Creating .xinitrc to start dwm..."
echo "exec dwm" > "$xinitrc_file"
chown "$SUDO_USER:$SUDO_USER" "$xinitrc_file"

echo "Creating .bash_profile to start X on tty1..."
cat > "$bash_profile_file" <<'EOF'
if [[ -z $DISPLAY ]] && [[ $(tty) = /dev/tty1 ]]; then
    startx
fi
EOF
chown "$SUDO_USER:$SUDO_USER" "$bash_profile_file"

# === ALSA SERVICE ===
if [[ ! -L "$alsa_service" ]]; then
  echo "Enabling ALSA audio service..."
  ln -s /etc/runit/sv/alsa "$alsa_service"
fi

echo
echo "Suckless environment installed. Log in on tty1 to start dwm."
