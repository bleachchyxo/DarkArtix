#!/bin/bash
# Enforce strict error handling
set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the necessary scripts using the correct path
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/select_storage.sh"
source "$SCRIPT_DIR/lib/partitioning.sh"
source "$SCRIPT_DIR/lib/base.sh"
source "$SCRIPT_DIR/lib/users.sh"
source "$SCRIPT_DIR/lib/timezone.sh"

echo "DarkArtix Installer v0.1"

# Detect firmware
if [ -d /sys/firmware/efi ]; then
  firmware="UEFI"
else
  firmware="BIOS"
fi

echo "Firmware: $firmware"
lsblk -dno NAME,SIZE,TYPE | awk '$3 == "disk" && $1 !~ /loop/ && $1 !~ /ram/ {print $1, $2}')

# Select a disk
disk_name=$(select_storage)
disk="/dev/$disk_name"
echo "You selected disk: $disk_name"

# Validate selected disk
validate_disk "$disk"
confirm_disk_wipe "$disk"
partition_disk "$disk"

# Mount partitions and bind mount system directories
mount_partitions "$disk"

# Base system installation
install_base_system "$disk"

# Timezone and locale configuration
set_timezone

# User and password configuration
set_root_password
set_user_password "$username"

# Chroot and final configuration
configure_chroot

# Cleanup
cleanup

echo "Installation complete. Please reboot and remove the installation media."
