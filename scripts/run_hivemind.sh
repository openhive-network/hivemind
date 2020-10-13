#!/bin/bash

function wait_for_accepting_db () {
    while ! pg_isready -h $POSTGRES_IP -p $POSTGRES_PORT ; do
        echo "Waiting for port $POSTGRES_IP $POSTGRES_PORT ..."
        sleep 10
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

function wait_for_finish () {
    while ping -c1 $1 &>/dev/null
    do
        echo "Waiting for $1 to finish"
        sleep 10
    done
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
    'wait_for_finish')
        wait_for_finish $2
    ;;
esac