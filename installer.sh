#!/bin/bash
set -euo pipefail

# Root check and firmware detection left as before...

# ...

# Timezone selection
message blue "Timezone selection"
echo "Available continents:"

# List valid continents (directories under /usr/share/zoneinfo)
mapfile -t continents_list < <(find /usr/share/zoneinfo -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | \
  grep -E '^(Africa|America|Antarctica|Arctic|Asia|Atlantic|Australia|Europe|Indian|Pacific)$' | sort)

echo "  ${continents_list[@]}"

continent_input=$(default_prompt "Continent" "America")
continent_lower=$(echo "$continent_input" | awk '{print tolower($0)}')

# Match user input to a valid continent name (case-insensitive)
selected_continent=""
for cont in "${continents_list[@]}"; do
  if [[ "${cont,,}" == "$continent_lower" ]]; then
    selected_continent="$cont"
    break
  fi
done

if [[ -z "$selected_continent" ]]; then
  echo "Invalid continent '$continent_input'. Please try again."
  exit 1
fi

# Now list countries inside the selected continent (these are directories)
echo "Available countries in $selected_continent:"
mapfile -t countries_list < <(find "/usr/share/zoneinfo/$selected_continent" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)

if [[ ${#countries_list[@]} -eq 0 ]]; then
  echo "No countries found in continent $selected_continent."
  exit 1
fi

# Display countries in columns with 14 rows per column
rows_per_column=14
total_countries=${#countries_list[@]}
columns_needed=$(( (total_countries + rows_per_column - 1) / rows_per_column ))

for (( row=0; row < rows_per_column; row++ )); do
  for (( col=0; col < columns_needed; col++ )); do
    idx=$(( col * rows_per_column + row ))
    if (( idx >= total_countries )); then
      if (( col == columns_needed -1 )); then
        break
      else
        printf "%-20s" ""
        continue
      fi
    fi
    printf "%-20s" "${countries_list[$idx]}"
  done
  echo
done

# Prompt for country selection
country_input=$(default_prompt "Country" "${countries_list[0]}")
country_lower=$(echo "$country_input" | awk '{print tolower($0)}')

selected_country=""
for country in "${countries_list[@]}"; do
  if [[ "${country,,}" == "$country_lower" ]]; then
    selected_country="$country"
    break
  fi
done

if [[ -z "$selected_country" ]]; then
  echo "Invalid country '$country_input'. Please try again."
  exit 1
fi

# List cities inside the selected country (files in directory)
echo "Available cities in $selected_country:"
mapfile -t cities_list < <(find "/usr/share/zoneinfo/$selected_continent/$selected_country" -type f -exec basename {} \; | sort)

if [[ ${#cities_list[@]} -eq 0 ]]; then
  echo "No cities found in country $selected_country."
  exit 1
fi

# Display cities in columns with 14 rows per column
total_cities=${#cities_list[@]}
columns_needed=$(( (total_cities + rows_per_column - 1) / rows_per_column ))

for (( row=0; row < rows_per_column; row++ )); do
  for (( col=0; col < columns_needed; col++ )); do
    idx=$(( col * rows_per_column + row ))
    if (( idx >= total_cities )); then
      if (( col == columns_needed -1 )); then
        break
      else
        printf "%-20s" ""
        continue
      fi
    fi
    printf "%-20s" "${cities_list[$idx]}"
  done
  echo
done

# Prompt for city selection
city_input=$(default_prompt "City" "${cities_list[0]}")
city_lower=$(echo "$city_input" | awk '{print tolower($0)}')

selected_city=""
for city in "${cities_list[@]}"; do
  if [[ "${city,,}" == "$city_lower" ]]; then
    selected_city="$city"
    break
  fi
done

if [[ -z "$selected_city" ]]; then
  echo "Invalid city '$city_input'. Please try again."
  exit 1
fi

timezone="$selected_continent/$selected_country/$selected_city"
echo "Selected timezone: $timezone"
