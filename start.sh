#!/bin/bash

echo "Start cassandra on port 9042 before running this script (for example using docker-compose)"
echo "Also build the application with maven before running this script"

. <(sed -rE -e '/^\s*$/d' -e 's/^/export /' .env)

env

mkdir -p $KC_SPI_MAP_STORAGE_FILE_DIR
./dist/target/dist/bin/kc.sh -v start-dev --debug
