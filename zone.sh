#!/usr/bin/env bash

message blue "Choose a continent;"
echo "Africa  America  Antarctica  Asia  Atlantic  Australia  Europe  Pacific"

continent=$(default_prompt "Continent" "America")
continent="$(tr '[:upper:]' '[:lower:]' <<< "$continent")"
continent="$(tr '[:lower:]' '[:upper:]' <<< "${continent:0:1}")${continent:1}"

echo
message blue "Choose a timezone in $continent;"
ls /usr/share/zoneinfo/"$continent"

city=$(default_prompt "City/Timezone" "New_York")

timezone="$continent/$city"
message blue "Selected timezone: $timezone"

confirmation "Apply timezone setting?" "yes"

ln -sf /usr/share/zoneinfo/"$timezone" /etc/localtime
message green "Timezone set to $timezone"
