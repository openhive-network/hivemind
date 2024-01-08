#!/bin/bash

set -euo pipefail

LIMIT=300 #seconds

DATABASE_URL=$1

wait_for_postgres() {
  echo "Waiting for postgres hosted by container at the URL: ${DATABASE_URL}."

  timeout $LIMIT bash -c "until psql \"${DATABASE_URL}\" -c \"SELECT hive.wait_for_ready_instance(ARRAY['hivemind_app'], '4 MIN'::interval);\" ; do sleep 3 ; done"

}

wait_for_postgres
