#! /bin/bash

set -euo pipefail

# clear out block processing startup time recorded by previous runs
rm -f /tmp/block_processing_startup_time.txt

# Logger function
function log () {
    local -r category=$1
    local -r message=$2
    local -r timestamp=$(date +"%F %T,%3N%:z")
    echo "[Entrypoint] $timestamp INFO  [$category] (main) $message"
}

log "global" "Parameters passed directly to Hivemind docker entrypoint: $*"

COMMAND="$1"
HIVEMIND_ARGS=()
ADD_MOCKS=${ADD_MOCKS:-false}
LOG_PATH=${LOG_PATH:-}
POSTGRES_URL=${POSTGRES_URL:-}
POSTGRES_ADMIN_URL=${POSTGRES_ADMIN_URL:-}
INSTALL_APP=0

while [ $# -gt 0 ]; do
  case "$1" in
    --database-url=*)
        export POSTGRES_URL="${1#*=}"
        ;;
    --database-admin-url=*)
        export POSTGRES_ADMIN_URL="${1#*=}"
        ;;
    # Added for compatibility with other app setup
    --postgres-url=*)
        export POSTGRES_URL="${1#*=}"
        export POSTGRES_ADMIN_URL="${1#*=}"
        ;;
    --add-mocks=*)
        ADD_MOCKS="${1#*=}"
        ;;
    --add-mocks)
        ADD_MOCKS=true
        ;;
    --install-app)
        INSTALL_APP=1
        ;;
    *)
        HIVEMIND_ARGS+=("$1")
  esac
  shift
done

log "global" "Collected Hivemind arguments: ${HIVEMIND_ARGS[*]}"
log "global" "Using PostgreSQL instance: $POSTGRES_URL"
log "global" "Using PostgreSQL Admin URL: $POSTGRES_ADMIN_URL"

run_hive() {
  local db_url=${1:-"${POSTGRES_URL}"}
  # shellcheck source=/dev/null
  source /home/hivemind/.hivemind-venv/bin/activate
  if [[ -n "$LOG_PATH" ]]; then
    log "run_hive" "Starting Hivemind with log $LOG_PATH"
    hive "${HIVEMIND_ARGS[@]}" --database-url="${db_url}" > >( tee -i "$LOG_PATH" ) 2>&1
  else
    log "run_hive" "Starting Hivemind..."
    hive "${HIVEMIND_ARGS[@]}" --database-url="${db_url}"
  fi
}

setup() {
  log "setup" "Setting up the database..."
  cd /home/hivemind/app
  ./setup_postgres.sh --postgres-url="${POSTGRES_ADMIN_URL}"
  ./install_app.sh --postgres-url="${POSTGRES_ADMIN_URL}"
  if [[ "$ADD_MOCKS" == "true" ]]; then
    log "setup" "Adding mocks to database..."
    # shellcheck source=/dev/null
    source /home/hivemind/.hivemind-venv/bin/activate
    ci/add-mocks-to-db.sh --postgres-url="${POSTGRES_ADMIN_URL}"
    deactivate
  fi

  HIVEMIND_ARGS=("build_schema")
  run_hive "${POSTGRES_ADMIN_URL}"
}

uninstall_app() {
  log "setup" "Cleaning up an application specific contents located in the database: ${POSTGRES_ADMIN_URL}"
  cd /home/hivemind/app
  ./uninstall_app.sh --postgres-url="${POSTGRES_ADMIN_URL}"
}

case "$COMMAND" in
    setup)
      setup
      ;;
    install_app)
      setup
      ;;
    uninstall_app)
      uninstall_app
      ;;
    sync)
      if [ "${INSTALL_APP}" -eq 1 ]; then
        log "global" "Running install_app step because it was requested via the --install-app argument"
        SAVED_HIVEMIND_ARGS=("${HIVEMIND_ARGS[@]}")
        setup
        HIVEMIND_ARGS=("${SAVED_HIVEMIND_ARGS[@]}")
        log "global" "Done running install_app, now running the block processor"
        echo ""
        echo ""
      fi
      # save off the time the block processor started, for use in the health check
      date --utc --iso-8601=seconds > /tmp/block_processing_startup_time.txt
      run_hive
      ;;
    *)
      run_hive
esac

log "global" "Exiting docker entrypoint..."
