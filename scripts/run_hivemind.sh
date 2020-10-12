#!/bin/bash

function wait_for_accepting_db () {
    while !  pg_isready -d $POSTGRES_DB -h $POSTGRES_IP -p $POSTGRES_PORT -U $POSTGRES_USER ; do
        echo "Waiting for port $POSTGRES_IP $POSTGRES_PORT ..."
        sleep 1
        ((counter++))
    done
}

function sync () {
    echo "Start initial sync."
    wait_for_accepting_db
    exec hive sync --exit-after-sync --steemd-url "{\"default\": \"${HIVE_SYNC_URL}\"}" --database-url $DATABASE_URL 
}

function server () {
    echo "Start server."
    exec hive server --steemd-url "{\"default\": \"${HIVE_SYNC_URL}\"}" --database-url $DATABASE_URL 
}

function sync_and_server () {
    echo "Start background sync and server."
    wait_for_accepting_db
    exec hive sync --steemd-url "{\"default\": \"${HIVE_SYNC_URL}\"}" --database-url $DATABASE_URL &
    exec hive server --steemd-url "{\"default\": \"${HIVE_SYNC_URL}\"}" --database-url $DATABASE_URL 
}

case "$1" in
    'sync')
        sync
    ;;
    'server')
        server
    ;;
    'sync_and_server')
        sync_and_server
    ;;
esac