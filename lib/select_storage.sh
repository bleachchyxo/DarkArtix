#!/bin/bash

# List available disks and select one
select_storage() {
  # Show the task message with [+] formatting
  print_message "Choosing a disk."

  # List available disks and their sizes
  print_message "Available disks:"
  
  # Gather disk information using lsblk, then loop through and display it
  mapfile -t disks < <(lsblk -dno NAME,SIZE,TYPE | awk '$3 == "disk" && $1 !~ /^(loop|ram)/ {print $1, $2}')
  
  # Print the available disks
  for disk_entry in "${disks[@]}"; do
    echo "  $disk_entry"
  done

  # Default disk is the first one in the list
  default_disk="${disks[0]%% *}"

  # Prompt the user to choose a disk, with the default being the first disk in the list
  disk_name=$(ask "Choose a disk where to install" "$default_disk")

  # Return the selected disk name
  echo "$disk_name"
}

# Validate the selected disk
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
