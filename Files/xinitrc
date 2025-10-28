#!/bin/sh

[ -f ~/.xprofile ] && . ~/.xprofile

pgrep -x xcompmgr >/dev/null || xcompmgr -C -t.25 -r2.2 -o.25 &

trap 'kill 0' EXIT

battery_icon() {
  case $1 in
    9[5-9]|100) echo "" ;;
    7[5-9]|8[0-9]|9[0-4]) echo "" ;;
    5[0-9]|6[0-9]|7[0-4]) echo "" ;;
    2[5-9]|3[0-9]|4[0-9]) echo "" ;;
    *) echo "" ;;
  esac
}

volume_icon() {
  [ "$2" = "off" ] && echo "" && return
  [ "$1" -eq 0 ] && echo "" && return
  [ "$1" -le 50 ] && echo "" && return
  echo ""
}

last_minute=""
last_volume=""
last_network=""
last_battery=""
last_battery_warn=""

while :; do
  updated=0

  # Time (updates once per minute)
  minute=$(date +%M)
  if [ "$minute" != "$last_minute" ]; then
    time_status=$(date '+%-I:%M %p')
    last_minute="$minute"
    updated=1
  fi

  # Volume (only if playback devices are detected)
  if aplay -l 2>/dev/null | grep -q '^card'; then
    set -- $(amixer get Master | awk -F'[][]' '/Mono:/||/Left:/ {gsub("%",""); print $2, $6; exit} /Playback.*%/ {gsub("%",""); print $2, $4; exit}')
    icon=$(volume_icon "$1" "$2")
    volume_status="$icon"
    [ "$2" = "off" ] && volume_status="$icon Muted"
    [ "$1" -eq 0 ] && [ "$2" != "off" ] && volume_status="$icon 0%"
    [ "$1" -gt 0 ] && [ "$2" != "off" ] && volume_status="$icon $1%"
  else
    volume_status=""
  fi

  if [ "$volume_status" != "$last_volume" ]; then
    last_volume="$volume_status"
    updated=1
  fi

  # Network
  network_status=" Offline"
  for device in /sys/class/net/*; do
    [ -f "$device/operstate" ] || continue
    [ "$(cat "$device/operstate")" = "up" ] || continue
    interface=$(basename "$device")
    case "$interface" in
      wl*) network_status=" $interface" ;;
      *)   network_status=" $interface" ;;
    esac
    break
  done

  if [ "$network_status" != "$last_network" ]; then
    last_network="$network_status"
    updated=1
  fi

  # Battery
  for battery in /sys/class/power_supply/BAT*; do
    [ -d "$battery" ] || continue
    capacity=$(cat "$battery/capacity")
    status=$(cat "$battery/status")
    icon=$(battery_icon "$capacity")
    [ "$status" = "Charging" ] && icon="⚡$icon"
    battery_status="$icon $capacity%"

    if [ "$capacity" -le 30 ] && [ "$battery_status" != "$last_battery_warn" ]; then
      notify-send "Low Battery" "Battery at $capacity%. Please charge."
      last_battery_warn="$battery_status"
    fi
    break
  done

  if [ "$battery_status" != "$last_battery" ]; then
    last_battery="$battery_status"
    updated=1
  fi

  # Status bar
  status=" $last_network"
  [ -n "$last_battery" ] && status="$status | $last_battery"
  [ -n "$last_volume" ] && status="$status | $last_volume"
  status="$status | $time_status "

  [ "$updated" -eq 1 ] && xsetroot -name "$status"

  sleep 1
done &

exec dwm
