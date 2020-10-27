#!/bin/bash

# Get postgresql server version

set -euo pipefail

get_postgres_version() {

    version=$(
        PGPASSWORD=$POSTGRES_PASSWORD psql -X -A -t \
            --username $POSTGRES_USER \
            --host $POSTGRES_HOST \
            --port ${POSTGRES_PORT} \
            --dbname postgres \
            -c "show server_version_num;"
        )
    echo $(echo $version | cut -c1-2)

}

get_postgres_version
