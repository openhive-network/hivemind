#!/bin/bash

set -euo pipefail

LIMIT=300 #seconds

DATABASE_URL=$1

wait_for_postgres() {
  echo "Waiting for postgres hosted by container at the URL: ${DATABASE_URL}."

  timeout $LIMIT bash -c "until psql "${DATABASE_URL}" -c 'SELECT * FROM hive.contexts;'; do sleep 3 ; done"
  timeout $LIMIT bash -c "until psql "${DATABASE_URL}" -c 'SELECT NOT EXISTS(SELECT 1 FROM hive.indexes_constraints);'; do sleep 3 ; done"
}

wait_for_postgres
