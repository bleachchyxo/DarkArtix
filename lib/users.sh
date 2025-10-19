#!/bin/bash

# Set root password
set_root_password() {
  print_message "Set root password:"
  while true; do
    read -s -p "Root password: " rootpass1; echo
    read -s -p "Confirm root password: " rootpass2; echo
    [[ "$rootpass1" == "$rootpass2" && -n "$rootpass1" ]] && break || echo "Passwords do not match or are empty. Try again."
  done
  echo "root:$rootpass1" | chpasswd
}

# Set user password
set_user_password() {
  local username="$1"
  print_message "Set password for user '$username':"
  while true; do
    read -s -p "User password: " userpass1; echo
    read -s -p "Confirm user password: " userpass2; echo
    [[ "$userpass1" == "$userpass2" && -n "$userpass1" ]] && break || echo "Passwords do not match or are empty. Try again."
  done
  echo "$username:$userpass1" | chpasswd
}
