#!/bin/bash

set -e
set -o pipefail

POSTGRES_HOST="localhost"
POSTGRES_PORT=5432
POSTGRES_USER="hivemind"
WEBSERVER_PORT=8080
ADMIN_PORT=3001



while [ $# -gt 0 ]; do
  case "$1" in
    --host=*)
        POSTGRES_HOST="${1#*=}"
        ;;
    --port=*)
        POSTGRES_PORT="${1#*=}"
        ;;
    --user=*)
        POSTGRES_USER="${1#*=}"
        ;;
    --webserver_port|--webserver-port=*)
        WEBSERVER_PORT="${1#*=}"
        ;;
    --admin_port|--admin-port=*)
        ADMIN_PORT="${1#*=}"
        ;;
    --postgres-url=*)
        POSTGRES_URL="${1#*=}"
        ;;
    -*)
        echo "ERROR: '$1' is not a valid option"
        echo
        exit 1
        ;;
    *)
        echo "ERROR: '$1' is not a valid argument"
        echo
        exit 2
        ;;
    esac
    shift
done

POSTGRES_ACCESS=${POSTGRES_URL:-"postgresql://$POSTGRES_USER@$POSTGRES_HOST:$POSTGRES_PORT/haf_block_log"}

start_webserver() { 
    export PGRST_DB_URI=$POSTGRES_ACCESS
    export PGRST_SERVER_PORT=$WEBSERVER_PORT
    export PGRST_ADMIN_SERVER_PORT=$ADMIN_PORT
    export PGRST_DB_ROOT_SPEC="home"

    postgrest postgrest.conf
}

start_webserver
