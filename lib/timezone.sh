#!/bin/bash

# Set timezone and locale
set_timezone() {
  timezone=$(ask "Enter your timezone (e.g., Europe/Berlin)" "UTC")
  ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
  hwclock --systohc
  locale-gen
}
