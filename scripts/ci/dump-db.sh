#!/bin/bash

set -euo pipefail

dump_db() {
    echo "Dumping database ${HIVEMIND_DB_NAME}"

    export PGPASSWORD=${RUNNER_POSTGRES_APP_USER_PASSWORD}
    exec_path=$POSTGRES_CLIENT_TOOLS_PATH/$POSTGRES_MAJOR_VERSION/bin

    echo "Using pg_dump version $($exec_path/pg_dump --version)"

    time $exec_path/pg_dump \
        --username="${RUNNER_POSTGRES_APP_USER}" \
        --host="${RUNNER_POSTGRES_HOST}" \
        --port="${RUNNER_POSTGRES_PORT}" \
        --dbname="${HIVEMIND_DB_NAME}" \
        --schema=public \
        --format=directory \
        --jobs=4 \
        --compress=6 \
        --quote-all-identifiers \
        --lock-wait-timeout=30000 \
        --no-privileges --no-acl \
        --verbose \
        --file="pg-dump-${HIVEMIND_DB_NAME}"

    unset PGPASSWORD
}

dump_db
