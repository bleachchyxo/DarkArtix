#!/bin/bash

# Ensure utils.sh is sourced for the ask function
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"

# List available disks and select one
select_storage() {
  # Print message before selecting disk
  print_message "Choosing a disk"

  # List available disks and their sizes using lsblk
  print_message "Listing available disks:"
  
  # Use lsblk to list disks and capture the output
  mapfile -t disks < <(lsblk -dno NAME,SIZE,TYPE | awk '$3 == "disk" && $1 !~ /loop/ && $1 !~ /ram/ {print $1, $2}')
  
  # Check if any disks were found
  if [ ${#disks[@]} -eq 0 ]; then
    echo "No valid disks found. Exiting."
    exit 1
  fi

  # Print the available disks
  for disk_entry in "${disks[@]}"; do
    echo "  $disk_entry"
  done

  # Set the default disk as the first in the list
  default_disk="${disks[0]%% *}"

  # Ask user to choose a disk, default to the first disk
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
