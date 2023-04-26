#! /bin/bash

set -euo pipefail

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

export MOCK_BLOCK_DATA_PATH="mock_data/block_data"
export MOCK_VOPS_DATA_PATH="mock_data/vops_data"

run_mocker() {
  echo "Creating hive.app_next_block() function wrapper"
  psql "${HAF_ADMIN_POSTGRES_URL}" -f "${SCRIPTPATH}/wrapper_for_app_next_block.sql"

  echo "Running mocking script"
  mocker --database-url "${HAF_ADMIN_POSTGRES_URL}"
}

run_mocker
