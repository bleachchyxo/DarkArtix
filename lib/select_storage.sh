#!/bin/bash

# List available disks and select one
select_storage() {
  # Use the print_message function to display the task
  print_message "Choosing a disk."

  # List available disks and their sizes
  mapfile -t disks < <(lsblk -dno NAME,SIZE,TYPE | awk '$3 == "disk" && $1 !~ /^(loop|ram)/ {print $1, $2}')
  echo "Available disks:"
  for disk_entry in "${disks[@]}"; do
    echo "  $disk_entry"
  done

  # Set default disk (first one in the list)
  default_disk="${disks[0]%% *}"

  # Prompt user to choose a disk, default to the first one in the list
  disk_name=$(ask "Choose a disk where to install" "$default_disk")

  # Return the selected disk name
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
