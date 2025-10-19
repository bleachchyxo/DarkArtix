#!/bin/bash

# List available disks and select one
select_storage() {
  # Show the task message with [+] formatting
  print_message "Choosing a disk."

  # List available disks and their sizes, using lsblk and filtering out unnecessary entries
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
