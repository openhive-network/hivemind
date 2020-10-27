#!/bin/bash

set -euo pipefail

cat << EOF
Starting hive sync using hived url: ${HIVED_URL}.
Max sync block is: ${HIVEMIND_MAX_BLOCK}.
EOF

# For debug only!
# HIVEMIND_MAX_BLOCK=10001
# HIVED_URL='{"default":"http://hived-node:8091"}'
# HIVED_URL='{"default":"http://172.17.0.1:8091"}'

DATABASE_URL="postgresql://${HIVEMIND_POSTGRES_USER}:${HIVEMIND_POSTGRES_USER_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${HIVEMIND_DB_NAME}"

hive sync \
    --log-mask-sensitive-data \
    --pid-file hive_sync.pid \
    --test-max-block=${HIVEMIND_MAX_BLOCK} \
    --exit-after-sync \
    --test-profile=False \
    --steemd-url "$HIVED_URL" \
    --prometheus-port 11011 \
    --database-url "$DATABASE_URL" \
    2>&1 | tee -i hivemind-sync.log
