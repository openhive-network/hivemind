#!/bin/bash

set -euo pipefail

# For debug only!
# RUNNER_HIVEMIND_SYNC_MAX_BLOCK=10000
# RUNNER_HIVED_URL='{"default":"http://hived-node:8091"}'
# RUNNER_HIVED_URL='{"default":"http://172.17.0.1:8091"}'

hive_sync() {
    # Start hive sync process

    cat << EOF
Starting hive sync using hived url: ${RUNNER_HIVED_URL}.
Max sync block is: ${RUNNER_HIVEMIND_SYNC_MAX_BLOCK}.
EOF

    USER=${RUNNER_POSTGRES_APP_USER}:${RUNNER_POSTGRES_APP_USER_PASSWORD}
    OPTIONS="host=${RUNNER_POSTGRES_HOST}&port=${RUNNER_POSTGRES_PORT}"
    DATABASE_URL="postgresql://${USER}@/${HIVEMIND_DB_NAME}?${OPTIONS}"

    hive sync \
        --log-mask-sensitive-data \
        --pid-file hive_sync.pid \
        --test-max-block=${RUNNER_HIVEMIND_SYNC_MAX_BLOCK} \
        --exit-after-sync \
        --test-profile=False \
        --steemd-url "${RUNNER_HIVED_URL}" \
        --prometheus-port 11011 \
        --database-url "${DATABASE_URL}" \
        --mock-block-data-path mock_data/block_data/follow_op/mock_block_data_follow.json mock_data/block_data/community_op/mock_block_data_community.json \
        --community-start-block 4999998 \
        2>&1 | tee -i hivemind-sync.log

}

hive_sync
