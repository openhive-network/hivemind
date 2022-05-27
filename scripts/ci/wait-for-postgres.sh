#!/bin/bash

# wait-for-postgres.sh

LIMIT=300 #seconds

CONTAINER_NAME=$1

wait_for_postgres() {
    counter=0
    echo "Waiting for postgres hosted by contaienr: ${CONTAINER_NAME}."

    #timeout $LIMIT bash -c "until docker exec $CONTAINER_NAME pg_isready ; do sleep 1 ; done"

    timeout $LIMIT bash -c "until psql --host ${CONTAINER_NAME} -d haf_block_log -U haf_app_admin -c 'SELECT * FROM hive.contexts;'; do sleep 3 ; done"
}

wait_for_postgres

