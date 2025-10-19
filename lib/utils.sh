#!/bin/bash

# Ask function for getting user input
ask() {
  local prompt="$1"
  local default="$2"
  read -rp "$prompt [$default]: " input
  echo "${input:-$default}"
}

# Confirm function to ask yes/no questions
confirm() {
  local prompt="$1"
  local default="${2:-no}"
  local yn_format
  [[ "${default,,}" =~ ^(yes|y)$ ]] && yn_format="[Y/n]" || yn_format="[y/N]"
  read -rp "$prompt $yn_format: " answer
  answer="${answer:-$default}"
  [[ "${answer,,}" =~ ^(yes|y)$ ]] || { echo "Aborted."; exit 1; }
}

# Print message with [+] formatting in green
print_message() {
  local message="$1"
  # Print [+] in green and the rest in normal color
  echo -e "\033[0;32m[+]\033[0m $message"
}
