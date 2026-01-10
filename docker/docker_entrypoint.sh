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

log "global" "Parameters passed directly to Hivemind docker entrypoint: '$*'"

SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"

COMMAND="$1"
HIVEMIND_ARGS=()
ADD_MOCKS=${ADD_MOCKS:-false}
LOG_PATH=${LOG_PATH:-}
POSTGRES_URL=${POSTGRES_URL:-}
POSTGRES_ADMIN_URL=${POSTGRES_ADMIN_URL:-}
INSTALL_APP=0
DO_SCHEMA_UPGRADE=0
WITH_APPS=0
REPTRACKER_SCHEMA=reptracker_app
SWAGGER_URL="{hivemind-host}"
STATEMENT_TIMEOUT=""
reptracker_dir="$SCRIPT_DIR/app/reputation_tracker"
hafah_dir="$SCRIPT_DIR/app/hafah"
haf_dir="$SCRIPT_DIR/haf"

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
    --statement-timeout=*)
        STATEMENT_TIMEOUT="${1#*=}"
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
    --swagger-url=*)
        SWAGGER_URL="${1#*=}"
        ;;
    --upgrade-schema)
        INSTALL_APP=1
        DO_SCHEMA_UPGRADE=1
        ;;
    --with-apps)
        WITH_APPS=1
        ;;
    *)
        arg=$1
        [[ -n "${arg}" ]] && HIVEMIND_ARGS+=("${arg}")
        ;;
  esac
  shift
done

log "global" "Collected Hivemind arguments: '${HIVEMIND_ARGS[*]}'"
log "global" "Using PostgreSQL instance: '$POSTGRES_URL'"
log "global" "Using PostgreSQL Admin URL: '$POSTGRES_ADMIN_URL'"

run_hive_no_exec() {
  local db_url=${1:-"${POSTGRES_URL}"}
  # shellcheck source=/dev/null
  source /home/hivemind/.hivemind-venv/bin/activate
  if [[ -n "$LOG_PATH" ]]; then
    log "run_hive" "Starting Hivemind with log '$LOG_PATH'"
    hive "${HIVEMIND_ARGS[@]}" --database-url="${db_url}" > >( tee -i "$LOG_PATH" ) 2>&1
  else
    log "run_hive" "Starting Hivemind..."
    hive "${HIVEMIND_ARGS[@]}" --database-url="${db_url}"
  fi
}

run_hive() {
  local db_url=${POSTGRES_URL}
  # shellcheck source=/dev/null
  source /home/hivemind/.hivemind-venv/bin/activate
  if [[ -n "$LOG_PATH" ]]; then
    log "run_hive" "Starting Hivemind with log '$LOG_PATH'"
    exec hive "${HIVEMIND_ARGS[@]}" --reptracker-schema-name="${REPTRACKER_SCHEMA}" --swagger-url="${SWAGGER_URL}" --database-url="${db_url}" > >( tee -i "$LOG_PATH" ) 2>&1
  else
    log "run_hive" "Starting Hivemind..."
    exec hive "${HIVEMIND_ARGS[@]}" --reptracker-schema-name="${REPTRACKER_SCHEMA}" --swagger-url="${SWAGGER_URL}" --database-url="${db_url}"
  fi
}

run_server() {
  local db_url=${POSTGRES_URL}
  # shellcheck source=/dev/null
  if [[ -n "$LOG_PATH" ]]; then
    log "run_hive" "Starting hivemind postgrest server with log $LOG_PATH"
    echo "Running postgrest setup..."
    exec "$SCRIPT_DIR/app/start_postgrest.sh" "${HIVEMIND_ARGS[@]}" --postgres-url="${POSTGRES_URL}" > >( tee -i "$LOG_PATH" ) 2>&1
  else
    log "run_hive" "Starting hivemind postgrest server..."
    echo "Running postgrest setup..."
    exec "$SCRIPT_DIR/app/start_postgrest.sh" "${HIVEMIND_ARGS[@]}" --postgres-url="${POSTGRES_URL}"
  fi
}


setup() {
  log "setup" "Setting up the database..."
  cd /home/hivemind/app
  # If STATEMENT_TIMEOUT was provided, pass it to setup_postgres.sh
  if [[ -n "${STATEMENT_TIMEOUT}" ]]; then
      ./setup_postgres.sh --postgres-url="${POSTGRES_ADMIN_URL}" --statement-timeout="${STATEMENT_TIMEOUT}"
  else
      ./setup_postgres.sh --postgres-url="${POSTGRES_ADMIN_URL}"
  fi

  if [ "${WITH_APPS}" -eq 1 ]; then
    # if we force to install rep tracker then we setup it as non-forking app
    # if we do not install it together with hivemind, then we get what we have forking or not
    pushd "$reptracker_dir"
    ./scripts/install_app.sh --postgres-url="${POSTGRES_ADMIN_URL}" --schema="${REPTRACKER_SCHEMA}" --is_forking="false"
    popd

    # Install hafah application
    pushd "$hafah_dir"
    ./scripts/setup_postgres.sh --postgres-url="${POSTGRES_ADMIN_URL}" --path-to-haf="${haf_dir}"
    ./scripts/install_app.sh --postgres-url="${POSTGRES_ADMIN_URL}"
    popd
  fi

  ./install_app.sh --reptracker-schema-name="${REPTRACKER_SCHEMA}" --postgres-url="${POSTGRES_ADMIN_URL}"

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

  if [ "${WITH_APPS}" -eq 1 ]; then
    "${SCRIPT_DIR}/app/reputation_tracker/scripts/uninstall_app.sh" --schema=${REPTRACKER_SCHEMA} --postgres-url="${POSTGRES_ADMIN_URL}"
    "${SCRIPT_DIR}/app/hafah/scripts/uninstall_app.sh" --postgres-url="${POSTGRES_ADMIN_URL}"
  fi
}

log "global" "Command: '${COMMAND}'"
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
        log "global" ""
        log "global" ""
      fi
      # save off the time the block processor started, for use in the health check
      date --utc --iso-8601=seconds > /tmp/block_processing_startup_time.txt
      run_hive
      ;;
    server)
      HIVEMIND_ARGS=("${HIVEMIND_ARGS[@]:1}")
      log "global" "Running Hivemind with arguments '${HIVEMIND_ARGS[*]}'"
      run_server
      ;;
    *)
      log "global" "COMMAND - first argument is not valid. Available commands: setup, install_app, uninstall_app, sync, server"
      ;;
esac

log "global" "Exiting docker entrypoint..."
