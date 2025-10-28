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

#!/bin/bash
set -euo pipefail

# Ensure script is run with sudo
if [[ -z "${SUDO_USER:-}" ]]; then
  echo "This script must be run with sudo."
  exit 1
fi

# Determine the real user
USER_DIR="/home/$SUDO_USER"

# Update system and installing packages
pacman -Syyu --noconfirm
pacman -S --noconfirm \
  gcc make git \
  patch curl \
  libx11 libxinerama libxft \
  xorg xorg-xinit \
  ttf-dejavu ttf-font-awesome \
  alsa-utils-runit \
  xcompmgr

# .config 
mkdir -p "$USER_DIR/.config"  # Using $SUDO_USER to point to correct home directory

# Cloning suckless repos with error handling
for repository in dwm dmenu st; do
  git -C "$USER_DIR/.config" clone --depth 1 "https://git.suckless.org/$repository" "$USER_DIR/.config/$repository" || { echo "Failed to clone $repository"; exit 1; }
done

# dmenu setup
sed -i 's/static int topbar = 1;/static int topbar = 0;/' "$USER_DIR/.config/dmenu/config.def.h"
make -C "$USER_DIR/.config/dmenu" install || { echo "dmenu compilation failed"; exit 1; }

# dwm setup with patches
curl -s -o "$USER_DIR/.config/dwm/dwm-fullgaps-20200508-7b77734.diff" https://dwm.suckless.org/patches/fullgaps/dwm-fullgaps-20200508-7b77734.diff
patch -d "$USER_DIR/.config/dwm" < "$USER_DIR/.config/dwm/dwm-fullgaps-20200508-7b77734.diff"
sed -i 's/static const unsigned int gappx     = 5;/static const unsigned int gappx     = 15;/' "$USER_DIR/.config/dwm/config.def.h"
sed -i '8s/topbar\s*=\s*1;/topbar = 0;/g' "$USER_DIR/.config/dwm/config.def.h"
sed -i 's/#define MODKEY Mod1Mask/#define MODKEY Mod4Mask/' "$USER_DIR/.config/dwm/config.def.h"
make -C "$USER_DIR/.config/dwm" install || { echo "dwm compilation failed"; exit 1; }
rm "$USER_DIR/.config/dwm/dwm-fullgaps-20200508-7b77734.diff"

# st setup with patches
curl -s -o "$USER_DIR/.config/st/st-alpha-20240814-a0274bc.diff" https://st.suckless.org/patches/alpha/st-alpha-20240814-a0274bc.diff
patch -d "$USER_DIR/.config/st" < "$USER_DIR/.config/st/st-alpha-20240814-a0274bc.diff"
curl -s -o "$USER_DIR/.config/st/st-blinking_cursor-20230819-3a6d6d7.diff" https://st.suckless.org/patches/blinking_cursor/st-blinking_cursor-20230819-3a6d6d7.diff
patch -d "$USER_DIR/.config/st" < "$USER_DIR/.config/st/st-blinking_cursor-20230819-3a6d6d7.diff"
sed -i 's|Liberation Mono:pixelsize=[0-9]*:antialias=true:autohint=true|Liberation Mono:pixelsize=26:antialias=true:autohint=true|' "$USER_DIR/.config/st/config.def.h"
sed -i 's/XK_Prior/XK_K/; s/XK_Next/XK_J/' "$USER_DIR/.config/st/config.def.h"
make -C "$USER_DIR/.config/st" install || { echo "st compilation failed"; exit 1; }
rm "$USER_DIR/.config/st/*.diff"

# Setting final details
ln -s /etc/runit/sv/alsa /etc/runit/runsvdir/default/
cat >> "$USER_DIR/.bash_profile" <<'EOF'
if [[ -z $DISPLAY ]] && [[ $(tty) = /dev/tty1 ]]; then
    startx
fi
EOF
chown "$SUDO_USER:$SUDO_USER" "$USER_DIR/.bash_profile"
cp "$(find "$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)" -type f -name xinitrc -print -quit)" "$(eval echo "~${SUDO_USER:-$(logname 2>/dev/null || id -un)}")/.xinitrc"
chown -R "$SUDO_USER:$SUDO_USER" "$USER_DIR/.config"
chown -R "$SUDO_USER:$SUDO_USER" "$USER_DIR/.xinitrc"

message green "Enviroment succesfully installed. Reboot or type startx."
