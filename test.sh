#!/bin/bash
set -euo pipefail

# Must run as sudo
if [[ -z "${SUDO_USER:-}" ]]; then
  echo "This script must be run with sudo."
  exit 1
fi

USER_HOME="/home/$SUDO_USER"
CONFIG_DIR="$USER_HOME/.config"
XINITRC_PATH="$USER_HOME/.xinitrc"
BASH_PROFILE_PATH="$USER_HOME/.bash_profile"
ALSA_SERVICE_LINK="/etc/runit/runsvdir/default/alsa"

echo "Updating package list and system..."
pacman -Syyu --noconfirm

echo "Installing required packages..."
pacman -S --noconfirm gcc make git libx11 libxinerama libxft xorg xorg-xinit ttf-dejavu ttf-font-awesome alsa-utils-runit xcompmgr curl patch

mkdir -p "$CONFIG_DIR"
cd "$CONFIG_DIR"

# Clone repos if missing
for repo in dwm dmenu st; do
  if [[ ! -d "$repo" ]]; then
    echo "Cloning $repo..."
    git clone "https://git.suckless.org/$repo"
  else
    echo "$repo already cloned, skipping."
  fi
done

# Fix ownership so user can edit everything
echo "Setting ownership of $CONFIG_DIR to $SUDO_USER..."
chown -R "$SUDO_USER:$SUDO_USER" "$CONFIG_DIR"

# === PATCH ST ===
cd st

echo "Applying st alpha patch..."
curl -L -o st-alpha.diff https://st.suckless.org/patches/alpha/st-alpha-20240814-a0274bc.diff
patch -p1 < st-alpha.diff
rm -f st-alpha.diff config.h

echo "Applying st blinking cursor patch..."
curl -L -o st-blinking_cursor.diff https://st.suckless.org/patches/blinking_cursor/st-blinking_cursor-20230819-3a6d6d7.diff
patch -p1 < st-blinking_cursor.diff
rm -f st-blinking_cursor.diff config.def.h.orig config.h x.c.orig

echo "Updating st font settings in config.def.h..."
sed -i 's/^static char \*font = .*/static char *font = "Liberation Mono:pixelsize=27:antialias=true:autohint=true";/' config.def.h

echo "Updating st shortcuts in config.def.h..."
sed -i '/static Shortcut shortcuts\[\] = {/,/};/{
  s/{ TERMMOD, *XK_Prior, *zoom, *{.f = +1} },/{ TERMMOD,              XK_K,           zoom,           {.f = +1} },/
  s/{ TERMMOD, *XK_Next, *zoom, *{.f = -1} },/{ TERMMOD,              XK_J,           zoom,           {.f = -1} },/
}' config.def.h

cd ..

# Patch dwm to use Mod4 as MODKEY if needed
DWM_CONFIG="$CONFIG_DIR/dwm/config.def.h"
if grep -q '#define MODKEY Mod1Mask' "$DWM_CONFIG"; then
  echo "Patching dwm to use Mod4 (Super) as MODKEY..."
  sed -i 's/#define MODKEY Mod1Mask/#define MODKEY Mod4Mask/' "$DWM_CONFIG"
  rm -f "$CONFIG_DIR/dwm/config.h"
fi

# Build and install dwm, dmenu, st
for program in dwm dmenu st; do
  echo "Building and installing $program..."
  chown -R "$SUDO_USER:$SUDO_USER" "$CONFIG_DIR/$program"
  sudo -u "$SUDO_USER" make -C "$CONFIG_DIR/$program" clean
  sudo make -C "$CONFIG_DIR/$program" install
done

# Setup .xinitrc to launch dwm
echo "Creating .xinitrc to launch dwm..."
echo "exec dwm" > "$XINITRC_PATH"
chown "$SUDO_USER:$SUDO_USER" "$XINITRC_PATH"

# Setup .bash_profile to start X on tty1
cat > "$BASH_PROFILE_PATH" <<'EOF'
if [[ -z $DISPLAY ]] && [[ $(tty) = /dev/tty1 ]]; then
    startx
fi
EOF
chown "$SUDO_USER:$SUDO_USER" "$BASH_PROFILE_PATH"

# Enable ALSA runit service if missing
if [[ ! -L "$ALSA_SERVICE_LINK" ]]; then
  echo "Enabling ALSA service with runit..."
  ln -s /etc/runit/sv/alsa "$ALSA_SERVICE_LINK"
fi

echo
echo "Suckless environment setup complete. Log in on tty1 to start dwm."
