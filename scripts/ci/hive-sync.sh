#!/bin/bash

set -euo pipefail

haf_sync() {
    # Start hive sync process from haf database

    echo Removing hivemind context and schema from HAF database
    psql "${HAF_POSTGRES_URL}" -c "SELECT hive.app_remove_context('hivemind_app');" || true
    psql "${HAF_POSTGRES_URL}" -c "DROP SCHEMA IF EXISTS hivemind_app CASCADE;"

    echo Starting hive sync using database URL: ${HAF_POSTGRES_URL}
    echo Max sync block is: ${RUNNER_HIVEMIND_SYNC_MAX_BLOCK}

    hive sync \
        --log-mask-sensitive-data \
        --pid-file hive_sync.pid \
        --test-max-block=${RUNNER_HIVEMIND_SYNC_MAX_BLOCK} \
        --test-profile=False \
        --prometheus-port 11011 \
        --database-url "${HAF_POSTGRES_URL}" \
        --community-start-block 4998000 \
        2>&1 | tee -i hivemind-sync.log
}

haf_sync
