#!/bin/bash

# Get postgresql server version

set -euo pipefail

get_postgres_version() {
    # Get major version of postgres server.
    version=$(
        PGPASSWORD=$RUNNER_POSTGRES_APP_USER_PASSWORD psql -X -A -t \
            --username $RUNNER_POSTGRES_APP_USER \
            --host $RUNNER_POSTGRES_HOST \
            --port ${RUNNER_POSTGRES_PORT} \
            --dbname postgres \
            -c "show server_version_num;"
        )
    echo $(echo $version | cut -c1-2)
}

get_postgres_version
