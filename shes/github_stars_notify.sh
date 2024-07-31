#!/bin/bash

# GitHub username
USER=$1
TOKEN=""

# GitHub API endpoint for fetching user repositories
API_URL="https://api.github.com/users/$USER/repos"
DATA_FILE="github_data.txt"
FIRST_RUN=true

if [ -z "$1" ]; then
    echo "Usage: github_stars_notify.sh username"
    exit 1
fi

# Check if the data file exists to determine if this is the first run
if [ ! -f "$DATA_FILE" ]; then
    touch "$DATA_FILE"
else
    FIRST_RUN=false
fi

while true; do
    # Fetch the repositories data using the token
    repos=$(curl -s -H "Authorization: ${TOKEN:+token $TOKEN}" "$API_URL")

    # Extract NAMES, STARS, and FORKS
    NAMES=$(echo "$repos" | grep -o '"full_name": "[^"]*"' | awk -F'"' '{print $4}')
    STARS=$(echo "$repos" | grep -o '"stargazers_count": [0-9]*' | grep -o '[0-9]\+')
    FORKS=$(echo "$repos" | grep -o '"forks_count": [0-9]*' | grep -o '[0-9]\+')

    if [ ${#NAMES} -lt 1 ]; then
        echo "$repos"
        continue
    fi

    # Convert multiline strings to arrays
    IFS=$'\n' read -r -d '' -a names_array <<< "$NAMES"
    IFS=$'\n' read -r -d '' -a stars_array <<< "$STARS"
    IFS=$'\n' read -r -d '' -a forks_array <<< "$FORKS"

    # Load previous data into simple arrays
    prev_names=()
    prev_stars=()
    prev_forks=()

    if [ -f "$DATA_FILE" ]; then
        while IFS=" " read -r name star fork; do
            prev_names+=("$name")
            prev_stars+=("$star")
            prev_forks+=("$fork")
        done < "$DATA_FILE"
    fi

    # Update data file and check for changes
    > "$DATA_FILE" # Clear file


    current_time=$(date "+%Y-%m-%d %H:%M:%S")
    echo "======== $current_time ========"
    for ((i=0; i<${#names_array[@]}; i++)); do
        name="${names_array[i]}"
        star="${stars_array[i]}"
        fork="${forks_array[i]}"

        echo "[$name] Stars: $star, Forks: $fork"
        echo "$name $star $fork" >> "$DATA_FILE"

        # Find previous star and fork count for the current repository
        prev_star=0
        prev_fork=0
        for ((j=0; j<${#prev_names[@]}; j++)); do
            if [ "${prev_names[j]}" == "$name" ]; then
                prev_star=${prev_stars[j]}
                prev_fork=${prev_forks[j]}
                break
            fi
        done

        # Calculate the increase in stars and forks
        star_increase=$((star - prev_star))
        fork_increase=$((fork - prev_fork))

        # Construct the notification message
        notification=""

        if (( star_increase > 0 )); then
            notification+="Star: $star (+$star_increase)"
        else
            notification+="Star: $star"
        fi

        if (( fork_increase > 0 )); then
            notification+=", Fork: $fork (+$fork_increase)"
        else
            notification+=", Fork: $fork"
        fi

        # Notify if there is an increase and it's not the first run
        if ! $FIRST_RUN && (( star_increase > 0 || fork_increase > 0 )); then
            osascript -e "display notification \"$notification\" with title \"$name\""
        fi
    done

    # Set FIRST_RUN to false after the first iteration
    FIRST_RUN=false

    # Wait for 120 second before the next check
    sleep 120
#    break
done
