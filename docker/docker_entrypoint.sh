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

SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"

COMMAND="$1"
HIVEMIND_ARGS=()
ADD_MOCKS=${ADD_MOCKS:-false}
LOG_PATH=${LOG_PATH:-}
POSTGRES_URL=${POSTGRES_URL:-}
POSTGRES_ADMIN_URL=${POSTGRES_ADMIN_URL:-}
POSTGREST_SERVER=0
INSTALL_APP=0
DO_SCHEMA_UPGRADE=0
SKIP_REPTRACKER=0
REPTRACKER_SCHEMA=reptracker_app
reptracker_dir="$SCRIPT_DIR/app/reputation_tracker"


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
    --reptracker-schema=*)
        REPTRACKER_SCHEMA="${1#*=}"
        ;;
    --upgrade-schema)
        INSTALL_APP=1
        DO_SCHEMA_UPGRADE=1
        ;;
    --only-hivemind)
        SKIP_REPTRACKER=1
        ;;
    *)
        HIVEMIND_ARGS+=("$1")
  esac
  shift
done

log "global" "Collected Hivemind arguments: ${HIVEMIND_ARGS[*]}"
log "global" "Using PostgreSQL instance: $POSTGRES_URL"
log "global" "Using PostgreSQL Admin URL: $POSTGRES_ADMIN_URL"


run_hive_no_exec() {
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

run_hive() {
  local db_url=${1:-"${POSTGRES_URL}"}
  # shellcheck source=/dev/null
  source /home/hivemind/.hivemind-venv/bin/activate
  if [[ -n "$LOG_PATH" ]]; then
    log "run_hive" "Starting Hivemind with log $LOG_PATH"
    if [[ "$POSTGREST_SERVER" = 1 ]]; then
      echo "Running postgrest setup..."
      exec "$SCRIPT_DIR/app/ci/start_postgrest.sh" "${HIVEMIND_ARGS[@]}" --postgres-url="${POSTGRES_URL}"
    else
      exec hive "${HIVEMIND_ARGS[@]}" --database-url="${db_url}" > >( tee -i "$LOG_PATH" ) 2>&1
    fi
  else
    log "run_hive" "Starting Hivemind..."
    if [[ "$POSTGREST_SERVER" = 1 ]]; then
      echo "Running postgrest setup..."
      exec "$SCRIPT_DIR/app/ci/start_postgrest.sh" "${HIVEMIND_ARGS[@]}" --postgres-url="${POSTGRES_URL}"
    else
      exec hive "${HIVEMIND_ARGS[@]}" --database-url="${db_url}"
    fi
  fi
}

setup() {
  log "setup" "Setting up the database..."
  cd /home/hivemind/app
  ./setup_postgres.sh --postgres-url="${POSTGRES_ADMIN_URL}"

  if [ "${SKIP_REPTRACKER}" -eq 0 ]; then
    # if we force to install rep tracker then we setup it as non-forking app
    # if we do not install it together with hivemind, then we get what we have forking or not
    pushd "$reptracker_dir"
    ./scripts/install_app.sh --postgres-url="${POSTGRES_ADMIN_URL}" --schema="$REPTRACKER_SCHEMA" --is_forking="false" 
    popd
  fi

  ./install_app.sh --postgres-url="${POSTGRES_ADMIN_URL}"
  
  if [[ "$ADD_MOCKS" == "true" ]]; then
    log "setup" "Adding mocks to database..."
    # shellcheck source=/dev/null
    source /home/hivemind/.hivemind-venv/bin/activate
    ci/add-mocks-to-db.sh --postgres-url="${POSTGRES_ADMIN_URL}"
    deactivate
  fi

  if [ "${DO_SCHEMA_UPGRADE}" -eq 1 ]; then
    HIVEMIND_ARGS=("upgrade_schema")
  else
    HIVEMIND_ARGS=("build_schema")
  fi

  run_hive_no_exec "${POSTGRES_ADMIN_URL}"
}

uninstall_app() {
  log "setup" "Cleaning up an application specific contents located in the database: ${POSTGRES_ADMIN_URL}"
  cd /home/hivemind/app
  ./uninstall_app.sh --postgres-url="${POSTGRES_ADMIN_URL}"

  if [ "${SKIP_REPTRACKER}" -eq 0 ]; then
    "${SCRIPT_DIR}/app/reputation_tracker/scripts/uninstall_app.sh" --postgres-url="${POSTGRES_ADMIN_URL}"
  fi

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
    postgrest-server)
      POSTGREST_SERVER=1
      HIVEMIND_ARGS=($(for i in "${HIVEMIND_ARGS[@]}"; do [[ "$i" != "postgrest-server" ]] && echo "$i"; done))
      run_hive
      ;;
    *)
      run_hive
esac

log "global" "Exiting docker entrypoint..."
