#!/bin/bash
echo "Current working directory: $(pwd)"
echo "Trying to source ./lib/utils.sh"
source ./lib/utils.sh
set -euo pipefail

# Source all the modules
source ./lib/utils.sh
source ./lib/disk.sh
source ./lib/partitioning.sh
source ./lib/base.sh
source ./lib/users.sh
source ./lib/timezone.sh

# Disk selection and partitioning
disk_name=$(select_disk)
disk="/dev/$disk_name"
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
