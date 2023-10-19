#! /bin/bash

set -euo pipefail

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

print_help () {
cat <<EOF
Usage: $0 [OPTION[=VALUE]]...
Adds mocks to the database

OPTIONS:
  --postgres-url=URL    Allows to specify a PostgreSQL URL
  -?,--help             Display this help screen and exit
EOF
}

export MOCK_BLOCK_DATA_PATH="mock_data/block_data"
export MOCK_VOPS_DATA_PATH="mock_data/vops_data"
HAF_ADMIN_POSTGRES_URL=${HAF_ADMIN_POSTGRES_URL:-}

while [ $# -gt 0 ]; do
  case "$1" in
    --postgres-url=*)
        HAF_ADMIN_POSTGRES_URL="${1#*=}"
        ;;
    -?|--help)
        print_help
        exit 0
        ;;
    -*)
        echo "ERROR: '$1' is not a valid option"
        echo
        print_help
        exit 1
        ;;
    *)
        echo "ERROR: '$1' is not a valid argument"
        echo
        print_help
        exit 2
        ;;
    esac
    shift
done

run_mocker() {
  echo "Creating hive.app_next_block() function wrapper"
  psql "${HAF_ADMIN_POSTGRES_URL}" -f "${SCRIPTPATH}/wrapper_for_app_next_block.sql"

  echo "Running mocking script"
  mocker --database-url "${HAF_ADMIN_POSTGRES_URL}"
}

run_mocker
