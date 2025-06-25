#!/usr/bin/env bash

# Check if already logged in
if [[ -f "/home/tinybird/.tinyb" ]]
then
    echo "Tinybird already logged in"
    exit 0
fi

# Login to Tinybird
tb login --method code
