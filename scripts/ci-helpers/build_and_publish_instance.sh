#!/bin/bash
#
# Build and publish Hivemind Docker images
# Thin wrapper that calls common-ci-configuration script
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/../.."

# Find common-ci-configuration (cloned by CI or local)
COMMON_CI_DIR="${COMMON_CI_DIR:-$SRC_DIR/common-ci-configuration}"
COMMON_SCRIPT="$COMMON_CI_DIR/haf-app-tools/scripts/build_and_publish_instance.sh"

if [[ ! -x "$COMMON_SCRIPT" ]]; then
    echo "ERROR: Common script not found: $COMMON_SCRIPT"
    echo "Set COMMON_CI_DIR to point to common-ci-configuration repo"
    exit 1
fi

exec "$COMMON_SCRIPT" --src-dir="$SRC_DIR" --project-name=hivemind "$@"
