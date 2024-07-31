#!/bin/bash

# GitHub username
USER=$1

# GitHub API endpoint for fetching user repositories
API_URL="https://api.github.com/users/$USER/repos"

if [ -z "$1" ]; then
    echo "Usage: github_projects.sh username"
    exit 1
fi

# Fetch the repositories data
repos=$(curl -s "$API_URL")

# Extract NAMES, STARS, and FORKS
NAMES=$(echo "$repos" | grep -o '"full_name": "[^"]*"' | awk -F'"' '{print $4}')
STARS=$(echo "$repos" | grep -o '"stargazers_count": [0-9]*' | grep -o '[0-9]\+')
FORKS=$(echo "$repos" | grep -o '"forks_count": [0-9]*' | grep -o '[0-9]\+')

# Convert multiline strings to arrays
IFS=$'\n' read -r -d '' -a names_array <<< "$NAMES"
IFS=$'\n' read -r -d '' -a stars_array <<< "$STARS"
IFS=$'\n' read -r -d '' -a forks_array <<< "$FORKS"

# Combine data and prepare for sorting
combined_data=()
for ((i=0; i<${#names_array[@]}; i++)); do
    combined_data+=("${stars_array[i]} ${names_array[i]} ${forks_array[i]}")
done

# Sort data by stars in descending order
sorted_data=$(printf "%s\n" "${combined_data[@]}" | sort -nr -k1)

# Output the sorted results
echo "$sorted_data" | while read -r line; do
    star=$(echo "$line" | awk '{print $1}')
    name=$(echo "$line" | awk '{print $2}')
    fork=$(echo "$line" | awk '{print $3}')
    echo "[$name] Stars: $star, Forks: $fork"
done