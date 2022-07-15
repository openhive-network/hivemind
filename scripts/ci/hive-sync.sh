#!/bin/bash

set -euo pipefail

# For debug only!
RUNNER_HIVEMIND_SYNC_MAX_BLOCK=5000024
# RUNNER_HIVED_URL='{"default":"http://hived-node:8091"}'
# RUNNER_HIVED_URL='{"default":"http://172.17.0.1:8091"}'

haf_sync() {
    # Start hive sync process from haf database

    echo Removing hivemind context and table from HAF database
    psql $HAF_POSTGRES_URL -c "SELECT hive.app_remove_context('hivemind_app');" || true
    psql $HAF_POSTGRES_URL -c "DROP SCHEMA IF EXISTS hivemind_app CASCADE;"
    psql $HAF_POSTGRES_URL -c "CREATE SCHEMA IF NOT EXISTS hivemind_app;"
    echo Removing hivemind context and schema from HAF database
    psql "${HAF_POSTGRES_URL}" -c "SELECT hive.app_remove_context('hivemind_app');" || true
    psql "${HAF_POSTGRES_URL}" -c "DROP SCHEMA IF EXISTS hivemind_app CASCADE;"

    cat << EOF
Starting hive sync using haf url: ${HAF_POSTGRES_URL}.
Max sync block is: ${RUNNER_HIVEMIND_SYNC_MAX_BLOCK}.
EOF
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
