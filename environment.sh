#!/bin/bash
set -euo pipefail

[[ -n "${SUDO_USER:-}" ]] || { echo "This script must be run with sudo."; exit 1; }

message() {
    case "$1" in
        green)  echo -e "\033[32m[+]\033[0m $2" ;;
        yellow) echo -e "\033[33m[+]\033[0m $2" ;;
        blue)   echo -e "\033[34m[+]\033[0m $2" ;;
        *)      echo "[+] $2" ;;
    esac
}

USER_DIR="/home/$SUDO_USER"

pacman -Syyu --noconfirm
pacman -S --noconfirm \
    gcc make git patch curl \
    libx11 libxinerama libxft \
    xorg xorg-xinit \
    ttf-dejavu ttf-font-awesome \
    alsa-utils-runit xcompmgr dunst libnotify

mkdir -p "$USER_DIR/.config"

git -C "$USER_DIR/.config" clone --depth 1 \
    "https://git.suckless.org/dmenu" \
    "$USER_DIR/.config/dmenu" || { echo "Failed to clone dmenu"; exit 1; }

sed -i 's/static int topbar = 1;/static int topbar = 0;/' \
    "$USER_DIR/.config/dmenu/config.def.h"

make -C "$USER_DIR/.config/dmenu" install || {
    echo "dmenu compilation failed"
    exit 1
}

git -C "$USER_DIR/.config" clone --depth 1 \
    "https://github.com/bleachchyxo/dwm" \
    "$USER_DIR/.config/dwm" || { echo "Failed to clone dwm"; exit 1; }

make -C "$USER_DIR/.config/dwm" install || {
    echo "dwm compilation failed"
    exit 1
}

git -C "$USER_DIR/.config" clone --depth 1 \
    "https://github.com/bleachchyxo/st" \
    "$USER_DIR/.config/st" || { echo "Failed to clone st"; exit 1; }

make -C "$USER_DIR/.config/st" install || {
    echo "st compilation failed"
    exit 1
}

ln -sf /etc/runit/sv/alsa /etc/runit/runsvdir/default/alsa

cat > "$USER_DIR/.bash_profile" <<'EOF'
if [[ -z $DISPLAY ]] && [[ $(tty) = /dev/tty1 ]]; then
    startx
fi
EOF

sed -i '/^[[:space:]]*#[[:space:]]*PS1=/d;/^PS1=/d' "$USER_DIR/.bashrc"
cat >> "$USER_DIR/.bashrc" <<'EOF'

PS1='\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w \[\e[1;34m\]\$\[\e[0m\] '
EOF

cp "$(dirname "$0")/Files/xinitrc" "$USER_DIR/.xinitrc"
chown "$SUDO_USER:$SUDO_USER" "$USER_DIR/.bash_profile" "$USER_DIR/.bashrc" "$USER_DIR/.xinitrc"
chown -R "$SUDO_USER:$SUDO_USER" "$USER_DIR/.config"

message green "Environment successfully installed. Reboot or type startx."
