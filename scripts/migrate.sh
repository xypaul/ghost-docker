#!/usr/bin/env bash

set -euo pipefail

# Check we're running as root
if [[ "$EUID" -ne 0 ]]
then
    echo "Sorry, this script must be run as root!"
    exit 1
fi

echo "WARNING: This script is currently in beta, please ensure you have a backup of your current installation!"

read -rp 'Are you sure you want to continue? (y/n): ' confirm

if [[ "x${confirm}" != "xy" ]]
then
    echo "Aborting..."
    exit 1
fi

# Check if we have jq installed
if [[ ! $(which jq) ]]
then
    echo "jq is not installed, please install it first"
    exit 1
fi

# Prompt for current installation location
read -rp 'Current installation location: ' current_location

if [[ -z "$current_location" ]]
then
    echo "Current installation location is required"
    exit 1
fi

# Start some safety checks

# Check whether we can find a Ghost-CLI installation
if [[ ! -f "${current_location}/.ghost-cli" ]]
then
    echo "Could not find a Ghost-CLI installation at ${current_location}"
    exit 1
fi

# Check whether we can find a Ghost installation
if [[ ! -d "${current_location}/content" ]]
then
    echo "Could not find a Ghost installation at ${current_location}"
    exit 1
fi

if [[ ! -f "${PWD}/.env" ]]
then
    echo "Ensure you have a .env file setup for the new installation before continuing"
    exit 1
fi

read -rp 'MySQL user to export the current database (must have permission to run mysqldump - defaults to root): ' mysql_user
mysql_user=${mysql_user:-root}

# Stop current installation
read -rp 'This script is about to stop the current installation whilst it migrates to the new installation. Are you sure you want to continue? (y/n): ' confirm

if [[ "x${confirm}" != "xy" ]]
then
    echo "Aborting..."
    exit 1
fi

systemctl stop nginx
systemctl disable nginx

systemctl stop "ghost_$(jq -r < "${current_location}/.ghost-cli" '.name')"
systemctl disable "ghost_$(jq -r < "${current_location}/.ghost-cli" '.name')"

# Create new installation directory
# TODO: Ensure this is safe?
mkdir -p "${PWD}/data/ghost/"

# Copy current installations content dir
rsync -qHPva "${current_location}/content/" "${PWD}/data/ghost/"

echo "Fixing user permissions..."
chown -R 1000:1000 "${PWD}/data/ghost/"

# Starting MySQL container to import the database
docker compose up db -d

# Dump MySQL database to data dir so we can import it
echo "This script is about to dump the MySQL database, please enter the MySQL password for ${mysql_user} when prompted"
mysqldump -u "${mysql_user}" -p --host="$(jq -r < "${current_location}"/config.production.json '.database.connection.host')" "$(jq -r < "${current_location}"/config.production.json '.database.connection.database')" > "$PWD"/data/ghost_import.sql

# We do this _after_ the dump since the user will likely take time to input their password anyway
# Wait for MySQL container to be ready
echo "Waiting for new MySQL container to be ready..."
timeout=120
counter=0
until [ "$(docker compose ps db --format json | jq -r '.Health')" = "healthy" ] || [ $counter -eq $timeout ]; do
    echo -n "."
    sleep 1
    ((counter++)) || true
done

if [ $counter -eq $timeout ]; then
    echo " Timeout waiting for MySQL to be ready"
    exit 1
fi

echo " MySQL is ready!"
echo "Importing database..."
docker compose exec -T db sh -c 'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD" $MYSQL_DATABASE' < "${PWD}/data/ghost_import.sql"

# Starting Ghost container
echo "Starting Ghost and Caddy containers..."
docker compose up ghost caddy -d
