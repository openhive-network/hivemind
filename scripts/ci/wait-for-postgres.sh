#!/bin/bash

# wait-for-postgres.sh

LIMIT=120 #seconds

CONTAINER_NAME=$1

wait_for_postgres() {
    counter=0
    echo "Waiting for postgres hosted by contaienr: ${CONTAINER_NAME}."

    timeout $LIMIT bash -c "until docker exec $CONTAINER_NAME pg_isready ; do sleep 1 ; done"
}

wait_for_postgres

