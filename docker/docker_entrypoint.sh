#! /bin/bash

set -euo pipefail 

SCRIPTDIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

cleanup () {
  echo "Performing cleanup...."
  python_pid=$(pidof 'python3')
  echo "python_pid: $python_pid"
  
  sudo -n kill -INT $python_pid

  echo "Waiting for hivemind finish..."
  tail --pid=$python_pid -f /dev/null || true
  echo "Hivemind app finish done."

  echo "Cleanup actions done."
}

trap cleanup INT QUIT TERM

HIVEMIND_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --database-url=*)
        POSTGRES_URL="${1#*=}"
        ;;
    --port=*)
        HTTP_PORT="${1#*=}"
        ;;
  *)
      HIVEMIND_ARGS+=("$1") 
    esac
    shift
done

pushd /home/hivemind/app

# temporary comment out - fully dockerized version needs separate steps
#./scripts/setup_postgres.sh --postgres-url=${POSTGRES_URL}
#./scripts/setup_db.sh --postgres-url=${POSTGRES_URL}

{
echo "Attempting to start Hivemind process..."
sudo -HEnu hivemind /bin/bash <<EOF
  source /home/hivemind/.hivemind-venv/bin/activate
  hive "${HIVEMIND_ARGS[@]}" --database-url="${POSTGRES_URL}"
EOF
echo "Hivemind process finished execution: $?"
} &

job_pid=$!

jobs -l

echo "waiting for job finish: $job_pid."
wait $job_pid || true

echo "Exiting docker entrypoint..."

