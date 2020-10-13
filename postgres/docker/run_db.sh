#!/bin/bash

function set_mode () {
    echo "Setting ${PGDATA} mode."
    #set data to know host user after initialization
    chown -R 1000 ${PGDATA}
    #set user mode
    chmod 755 ${PGDATA}
}

function init () {
    if [ "$(ls ${PGDATA})" ]; then
        echo "Data dir ${PGDATA} is not empty, please clean it first."
        exit 0
    fi

    if [ ! "$(ls /docker-entrypoint-initdb.d)" ]; then
        echo "Init dir /docker-entrypoint-initdb.d is empty, abort init."
        exit 0
    fi

    echo "Start initilizing db."
    exec docker-entrypoint.sh postgres -c config_file=/etc/postgresql.conf &
    INIT_PID=$!
    while ! pg_isready -h 0.0.0.0 -p 5432 ; do
        echo "Database 0.0.0.0 5432 is being initialized... Please wait."
        sleep 10
    done
    #stop init process
    echo "Stoping initilizing db."
    kill $INIT_PID
    wait $INIT_PID
    set_mode
}

function run () {
    echo "Starting postgres db."
    exec docker-entrypoint.sh postgres -c config_file=/etc/postgresql.conf
    echo "Stoping postgres db."
}

function wait_for_finish () {
    while ping -c1 $1 &>/dev/null
    do
        echo "Waiting for $1 to finish"
        sleep 10
    done
}

case "$1" in
    'init')
        init
    ;;
    'run')
        run
    ;;
    'wait_for_finish')
        wait_for_finish $2
    ;;
esac

