#!/bin/bash

# List available disks and select one
select_disk() {
  # Use the print_message function to display the task
  print_message "Choosing a disk."

  # List available disks and their sizes, using lsblk and filtering out unnecessary entries
  print_message "Available disks:"

  # Gather disk information using lsblk, then loop through and display it
  disks=$(lsblk -dno NAME,SIZE,TYPE | awk '$3 == "disk" && $1 !~ /loop/ && $1 !~ /ram/ {print $1, $2}')

  # Debug output: Display the captured disk list
  echo "Disks found:"
  echo "$disks"

  # Set default disk (first one in the list)
  default_disk=$(echo "$disks" | head -n 1 | awk '{print $1}')

  # Prompt user to choose a disk, default to the first one in the list
  disk_name=$(ask "Choose a disk to install" "$default_disk")

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
