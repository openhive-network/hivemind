#! /bin/bash

set -euo pipefail

# Logger function
function log () {
    local -r category=$1
    local -r message=$2
    local -r timestamp=$(date +"%F %T,%3N%:z")
    echo "[Entrypoint] $timestamp INFO  [$category] (main) $message"
}

log "global" "Hivemind arguments: $*"

COMMAND="$1"
HIVEMIND_ARGS=()
ADD_MOCKS=${ADD_MOCKS:-false}
LOG_PATH=${LOG_PATH:-}
POSTGRES_URL=${POSTGRES_URL:-}
POSTGRES_ADMIN_URL=${POSTGRES_ADMIN_URL:-}

while [ $# -gt 0 ]; do
  case "$1" in
    --database-url=*)
        POSTGRES_URL="${1#*=}"
        ;;
    --database-admin-url=*)
        POSTGRES_ADMIN_URL="${1#*=}"
        ;;
    --add-mocks=*)
        ADD_MOCKS="${1#*=}"
        ;;
    --add-mocks)
        ADD_MOCKS=true
        ;;
    *)
        HIVEMIND_ARGS+=("$1") 
  esac
  shift
done

log "global" "Hivemind arguments: ${HIVEMIND_ARGS[*]}"
log "global" "Using PostgreSQL instance: $POSTGRES_URL"

run_hive() {
  # shellcheck source=/dev/null
  source /home/hivemind/.hivemind-venv/bin/activate
  if [[ -n "$LOG_PATH" ]]; then
    log "run_hive" "Starting Hivemind with log $LOG_PATH"
    hive "${HIVEMIND_ARGS[@]}" --database-url="${POSTGRES_URL}" 2>&1 | tee -i "$LOG_PATH"
  else
    log "run_hive" "Starting Hivemind..."
    hive "${HIVEMIND_ARGS[@]}" --database-url="${POSTGRES_URL}"
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
}

case "$COMMAND" in
    setup)
      setup
      ;;
    *)
      run_hive
esac

log "global" "Exiting docker entrypoint..."