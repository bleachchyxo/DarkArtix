#!/bin/bash

# List available disks and select one
select_disk() {
  print_message "Detecting available disks..."
  mapfile -t disks < <(lsblk -dno NAME,SIZE,TYPE | awk '$3 == "disk" && $1 !~ /^(loop|ram)/ {print $1, $2}')
  for disk_entry in "${disks[@]}"; do
    echo "  $disk_entry"
  done
  disk_name=$(ask "Choose a disk to install" "${disks[0]%% *}")
  echo "$disk_name"
}

# Validate selected disk
validate_disk() {
  local disk="$1"
  if [[ ! -b "$disk" ]]; then
    echo "Invalid disk: $disk"
    exit 1
  fi
}

# Confirm disk wipe before proceeding
confirm_disk_wipe() {
  local disk="$1"
  confirm "This will erase all data on $disk. Continue?" "no"
}
