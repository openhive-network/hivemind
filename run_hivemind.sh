#!/bin/bash

function wait_for_accepting_db () {
    counter=0
    while !  pg_isready -d $POSTGRES_DB -h $POSTGRES_IP -p $POSTGRES_PORT -U $POSTGRES_USER ; do
        echo "waiting for port $POSTGRES_IP $POSTGRES_PORT ..."
        sleep 1
        if [ $counter -eq 10 ]; then 
            echo "Timeout reached... exiting."
            exit -1
        fi
        ((counter++))
    done
}

function alter_db_settings () {
    if [ -f "/src/hivemind/postgres.auto.conf" ]; then
        while read line; do
            psql -U tester -d hivemind -c "ALTER SYSTEM SET $line ;"
        done < /src/hivemind/postgres.auto.conf
        service postgresql restart
    fi
}

function start_db () {
    echo "Start postgres db."
    docker-entrypoint.sh postgres  &
    wait_for_accepting_db
    alter_db_settings
    wait_for_accepting_db
}

function start_sync () {
    echo "Start initial sync."
    hive sync --exit-after-sync --steemd-url "{\"default\": \"${HIVE_SYNC_URL}\"}" --database-url $DATABASE_URL 
}

function start_sync_and_server () {
    echo "Start background sync and server."
    hive sync --steemd-url "{\"default\": \"${HIVE_SYNC_URL}\"}" --database-url $DATABASE_URL &
    hive server --steemd-url "{\"default\": \"${HIVE_SYNC_URL}\"}" --database-url $DATABASE_URL 
}

start_db
start_sync
start_sync_and_server