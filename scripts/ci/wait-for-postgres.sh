#!/bin/sh

# wait-for-postgres.sh
# Use in docker-compose:
# command: ["./wait-for-postgres.sh", "name-of-postgres-service", "python", "app.py"]

set -e

LIMIT=30 #seconds
shift
cmd="$@"

wait_for_postgres() {
    # wkedzierski@syncad.com work, but customized by wbarcik@syncad.com
    counter=0
    echo "Waiting for postgres on ${POSTGRES_HOST}:${POSTGRES_PORT}. Timeout is ${LIMIT}s."
    while ! pg_isready \
            --username $ADMIN_POSTGRES_USER \
            --host $POSTGRES_HOST \
            --port $POSTGRES_PORT \
            --dbname postgres \
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
    PGPASSWORD=$ADMIN_POSTGRES_USER_PASSWORD psql \
            --username "$ADMIN_POSTGRES_USER" \
            --host "$POSTGRES_HOST" \
            --port $POSTGRES_PORT \
            --dbname postgres <<EOF
SELECT version();
select name, setting, unit from pg_settings;
\copy (select * from pg_settings) to '$DIR/pg_settings_on_start.csv' WITH CSV HEADER
\q
EOF
    echo "-------------------------------------------------"

}

wait_for_postgres
output_configuration
