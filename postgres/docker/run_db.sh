#!/bin/bash

set -e

function init () {
    if [ "$(ls -l ${PGDATA})" ]; then
        echo "Data dir ${PGDATA} is not empty, please clean it first."
        exit 0
    fi
    echo "Start initilizing db."
    docker-entrypoint.sh postgres -c config_file=/etc/postgresql.conf &
    INIT_PID=$!
    while ! pg_isready -h $POSTGRES_IP -p $POSTGRES_PORT ; do
        echo "Database $POSTGRES_IP $POSTGRES_PORT is being initialized... Please wait."
        sleep 10
    done
    #stop init process
    kill $INIT_PID
    wait $INIT_PID
    #set data to know host user after initialization
    chown -R 1000 /var/lib/postgresql/data
    #set user mode
    chmod 755 /var/lib/postgresql/data
}

function run () {
    exec docker-entrypoint.sh postgres -c config_file=/etc/postgresql.conf
    #set data to know host user after initialization
    chown -R 1000 /var/lib/postgresql/data
    #set user mode
    chmod 755 /var/lib/postgresql/data
}

case "$1" in
    'init')
        init
    ;;
    'run')
        run
    ;;
esac

