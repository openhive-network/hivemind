#! /bin/bash

set -euo pipefail

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

# shellcheck disable=SC2034
LOG_FILE=install_app.log
# shellcheck source=./common.sh
source "$SCRIPTPATH/common.sh"

log_exec_params "$@"

# Script reponsible for execution of all actions required to finish configuration of the database holding a HAF database to work correctly with hivemind.

print_help () {
    echo "Usage: $0 [OPTION[=VALUE]]..."
    echo
    echo "Allows to setup a database already filled by HAF instance, to work with hivemind application."
    echo "OPTIONS:"
    echo "  --host=VALUE         Allows to specify a PostgreSQL host location (defaults to /var/run/postgresql)"
    echo "  --port=NUMBER        Allows to specify a PostgreSQL operating port (defaults to 5432)"
    echo "  --postgres-url=URL   Allows to specify a PostgreSQL URL (in opposite to separate --host and --port options)"
    echo "  --help               Display this help screen and exit"
    echo
}

POSTGRES_HOST="/var/run/postgresql"
POSTGRES_PORT=5432
POSTGRES_URL=""
REPTRACKER_SCHEMA="reptracker_app"


while [ $# -gt 0 ]; do
  case "$1" in
    --host=*)
        POSTGRES_HOST="${1#*=}"
        ;;
    --port=*)
        POSTGRES_PORT="${1#*=}"
        ;;
    --postgres-url=*)
        POSTGRES_URL="${1#*=}"
        ;;
    --reptracker-schema-name=*)
        REPTRACKER_SCHEMA="${1#*=}"
        ;;
    --help)
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

if [ -z "$POSTGRES_URL" ]; then
  POSTGRES_ACCESS="postgresql://haf_admin@$POSTGRES_HOST:$POSTGRES_PORT/haf_block_log"
else
  POSTGRES_ACCESS=$POSTGRES_URL
fi

psql "$POSTGRES_ACCESS" -v ON_ERROR_STOP=on -v REPTRACKER_SCHEMA="${REPTRACKER_SCHEMA}" -f "${SCRIPTPATH}/install_app.sql"

echo "Grant permissions to reptracker schema."
psql "$POSTGRES_ACCESS" -v ON_ERROR_STOP=on -c "GRANT reptracker_owner TO hivemind;"
psql "$POSTGRES_ACCESS" -v ON_ERROR_STOP=on -c "GRANT reptracker_user TO hivemind;"

echo "Grant permissions to hafah schema."
psql "$POSTGRES_ACCESS" -v ON_ERROR_STOP=on -c "GRANT hafah_owner TO hivemind;"
psql "$POSTGRES_ACCESS" -v ON_ERROR_STOP=on -c "GRANT hafah_user TO hivemind;"
