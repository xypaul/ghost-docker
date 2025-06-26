#!/usr/bin/env bash

# If arguments are provided, run tb command with those arguments
if [[ $# -gt 0 ]]; then
    # Check if logged in first
    if [[ ! -f "/home/tinybird/.tinyb" ]]; then
        echo "Not logged in to Tinybird. Please run 'docker compose run --rm tinybird-login' first"
        exit 1
    fi
    # Run the tb command with provided arguments
    exec tb "$@"
fi

# Default behavior: login
# Check if already logged in
if [[ -f "/home/tinybird/.tinyb" ]]
then
    echo "Tinybird already logged in"
    exit 0
fi

# Login to Tinybird
tb login --method code
