#! /bin/bash

set -euo pipefail

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

# shellcheck disable=SC2034
LOG_FILE=setup_postgres.log
# shellcheck source=./common.sh
source "$SCRIPTPATH/common.sh"

log_exec_params "$@"

# Script responsible for setup of specified postgres instance.
#
# - creates all builtin hivemind roles on pointed PostgreSQL server instance

print_help () {
    echo "Usage: $0 [OPTION[=VALUE]]..."
    echo
    echo "Allows to setup a database already filled by HAF instance, to work with hivemind application."
    echo "OPTIONS:"
    echo "  --host=VALUE               Allows to specify a PostgreSQL host location (defaults to /var/run/postgresql)"
    echo "  --port=NUMBER              Allows to specify a PostgreSQL operating port (defaults to 5432)"
    echo "  --postgres-url=URL         Allows to specify a PostgreSQL URL (in opposite to separate --host and --port options)"
    echo "  --statement-timeout=VALUE  Set the statement_timeout for the hivemind_user role (e.g., 10s)"
    echo "  --help                   Display this help screen and exit"
    echo
}

supplement_builtin_roles() {
  local pg_access="$1"
  echo "Attempting to supplement definition of hivemind builtin roles..."
  psql $pg_access -v ON_ERROR_STOP=on -c 'GRANT hivemind TO haf_admin;'
  psql $pg_access -v ON_ERROR_STOP=on -c 'GRANT hivemind_user TO hivemind;'
}

POSTGRES_HOST="/var/run/postgresql"
POSTGRES_PORT=5432
POSTGRES_URL=""
STATEMENT_TIMEOUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --host=*)
        POSTGRES_HOST="${1#*=}"
        ;;
    --port=*)
        POSTGRES_PORT="${1#*=}"
        ;;
    --postgres-url=*)
        export POSTGRES_URL="${1#*=}"
        ;;
    --statement-timeout=*)
        STATEMENT_TIMEOUT="${1#*=}"
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
  POSTGRES_ACCESS="postgresql://haf_admin@${POSTGRES_HOST}:${POSTGRES_PORT}/haf_block_log"
else
  POSTGRES_ACCESS=$POSTGRES_URL
fi

"$SCRIPTPATH/../haf/scripts/create_haf_app_role.sh" --postgres-url="$POSTGRES_ACCESS" --haf-app-account="hivemind"
"$SCRIPTPATH/../haf/scripts/create_haf_app_role.sh" --postgres-url="$POSTGRES_ACCESS" --haf-app-account="hivemind_user" --base-group="hive_applications_group"

#psql "$POSTGRES_ACCESS" -c "GRANT SET ON PARAMETER log_min_messages TO hivemind;"

supplement_builtin_roles "$POSTGRES_ACCESS"

if [ -n "$STATEMENT_TIMEOUT" ]; then
    echo "Setting statement timeout for hivemind_user role to ${STATEMENT_TIMEOUT}..."
    psql "$POSTGRES_ACCESS" -v ON_ERROR_STOP=on -c "ALTER ROLE hivemind_user SET statement_timeout TO '${STATEMENT_TIMEOUT}';"
fi
psql "$POSTGRES_ACCESS" -v ON_ERROR_STOP=on -c "ALTER ROLE hivemind_user RESET query_supervisor.limits_enabled;"
