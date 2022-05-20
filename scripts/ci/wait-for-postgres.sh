#!/bin/sh

# wait-for-postgres.sh
# Use in docker-compose:
# command: ["./wait-for-postgres.sh", "name-of-postgres-service", "python", "app.py"]

set -e

LIMIT=10 #seconds

HOST=$1
PORT=$2

if [ -z "$HOST" ]
then
    HOST="$RUNNER_POSTGRES_HOST"
fi
if [ -z "$PORT" ]
then
    PORT="$RUNNER_POSTGRES_PORT"
fi

wait_for_postgres() {
    counter=0
    echo "Waiting for postgres on ${HOST}:${PORT}."
    while ! pg_isready \
            --host $HOST \
            --port $PORT \
            --timeout=1 --quiet; do
        counter=$((counter+1))
        sleep 1
        if [ $counter -eq $LIMIT ]; then
            echo "Timeout reached, postgres is unavailable, exiting."
            exit 1
        fi
    done
}

output_configuration() {

    mkdir -p pg-stats
    DIR=$PWD/pg-stats

    echo "Postgres is up (discovered after ${counter}s)."
    echo "-------------------------------------------------"
    echo "Postgres version and configuration"
    echo "-------------------------------------------------"
    psql --username "$RUNNER_POSTGRES_ADMIN_USER" \
            --host "$HOST" \
            --port $PORT \
            --dbname postgres <<EOF
SELECT version();
-- select name, setting, unit from pg_settings;
-- show all;
\copy (select name, setting, unit from pg_settings) to '$DIR/pg_settings_on_start.csv' WITH CSV HEADER
\q
EOF
    echo "-------------------------------------------------"

}

wait_for_postgres
output_configuration
