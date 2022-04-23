#!/bin/bash

set -euo pipefail

# For debug only!
RUNNER_HIVEMIND_SYNC_MAX_BLOCK=5000024
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
        --test-profile=False \
        --steemd-url "${RUNNER_HIVED_URL}" \
        --prometheus-port 11011 \
        --database-url "${DATABASE_URL}" \
        --mock-block-data-path mock_data/block_data/follow_op/mock_block_data_follow.json \
          mock_data/block_data/follow_op/mock_block_data_follow_tests.json \
          mock_data/block_data/community_op/mock_block_data_community.json \
          mock_data/block_data/reblog_op/mock_block_data_reblog.json \
          mock_data/block_data/reblog_op/mock_block_data_reblog_delete.json \
          mock_data/block_data/payments_op/mock_block_data_payments.json \
          mock_data/block_data/notify_op/mock_block_data.json \
        --mock-vops-data-path mock_data/block_data/community_op/mock_vops_data_community.json \
        --community-start-block 4998000 \
        2>&1 | tee -i hivemind-sync.log

}

hive_sync
