#!/bin/bash

# ./run_server_sync.sh 5000024 "postgresql://user:password@localhost:5432/haf_block_log"

export RUNNER_HIVEMIND_SYNC_MAX_BLOCK=$1
export HAF_POSTGRES_URL=$2

HIVE_SYNC_PATH="./scripts/ci/hive-sync.sh"

"$HIVE_SYNC_PATH"
