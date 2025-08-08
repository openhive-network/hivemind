#! /bin/bash

set -xeuo pipefail

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

BASE_DIR="${SCRIPTPATH}"
SWAGGER_DIR="${BASE_DIR}/../../build"

poetry run -C "${BASE_DIR}" python  "${BASE_DIR}"/generate_hivemind_api_client.py "${BASE_DIR}" "${SWAGGER_DIR}"
