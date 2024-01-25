#! /bin/bash

set -euo pipefail

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

# shellcheck disable=SC2034
LOG_FILE=run_instance.log
# shellcheck source=./common.sh
source "$SCRIPTPATH/common.sh"

log_exec_params "$@"

# Script reponsible for execution of all actions required to finish configuration of the database holding a HAF database to work correctly with hivemind.

print_help () {
    echo "Usage: $0 [OPTION[=VALUE]]..."
    echo
    echo "Allows to setup a database already filled by HAF instance, to work with hivemind application."
    echo "OPTIONS:"
    echo "  --host=VALUE           Allows to specify a PostgreSQL host location (defaults to /var/run/postgresql)"
    echo "  --port=NUMBER          Allows to specify a PostgreSQL operating port (defaults to 5432)"
    echo "  --postgres-url=URL     Allows to specify a PostgreSQL URL (in opposite to separate --host and --port options)"
    echo "  --name=CONTAINER_NAME  Allows to specify a dedicated name to the spawned container instance"
    echo "  --detach               Allows to start container instance in detached mode. Otherwise, you can detach using Ctrl+p+q key binding"
    echo "  --docker-option=OPTION Allows to specify additional docker option, to be passed to underlying docker run spawn."
    echo "  --help                 Display this help screen and exit"
    echo
}

DOCKER_ARGS=()
HIVEMIND_ARGS=()

CONTAINER_NAME=hivemind-instance
IMAGE_NAME=

add_docker_arg() {
  local arg="$1"
#  echo "Processing docker argument: ${arg}"
  
  DOCKER_ARGS+=("$arg")
}

add_hivemind_arg() {
  local arg="$1"
#  echo "Processing hived argument: ${arg}"
  
  HIVEMIND_ARGS+=("$arg")
}


POSTGRES_HOST="/var/run/postgresql"
POSTGRES_PORT=5432
POSTGRES_URL=""

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
        add_hivemind_arg "--postgres-url=${POSTGRES_URL}"
        ;;
    --http-server-port=*)
        HTTP_ENDPOINT="${1#*=}"
        add_docker_arg "--publish=${HTTP_ENDPOINT}:8080"
        ;;
    --docker-option=*)
        option="${1#*=}"
        add_docker_arg "$option"
        ;; 
     --name=*)
        CONTAINER_NAME="${1#*=}"
        echo "Container name is: $CONTAINER_NAME"
        ;;
    --detach)
      add_docker_arg "--detach"
      ;;
    --help)
        print_help
        exit 0
        ;;
    *)
        if [ -z "$IMAGE_NAME" ]; then
            IMAGE_NAME="${1}"
            echo "Using image name: $IMAGE_NAME"
        else
          add_hivemind_arg "${1}"
        fi
        ;;
    esac
    shift
done

if [ -z "$POSTGRES_URL" ]; then
  POSTGRES_ACCESS="postgresql://hivemind@$POSTGRES_HOST:$POSTGRES_PORT/haf_block_log"
else
  POSTGRES_ACCESS=$POSTGRES_URL
fi

CMD_ARGS=("$@")
CMD_ARGS+=("${HIVEMIND_ARGS[@]}")

docker container rm -f -v "$CONTAINER_NAME" 2>/dev/null || true

docker run --rm -it -e UID=$(id -u) -e GID=$(id -g) --name "$CONTAINER_NAME" --stop-timeout=180 ${DOCKER_ARGS[@]} -e POSTGRES_URL="${POSTGRES_ACCESS}" "${IMAGE_NAME}" "${CMD_ARGS[@]}"

