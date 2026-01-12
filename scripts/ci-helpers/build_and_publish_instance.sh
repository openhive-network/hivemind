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

# If not found locally, download from GitLab
if [[ ! -x "$COMMON_SCRIPT" ]]; then
    echo "Common script not found locally, downloading from GitLab..."
    COMMON_CI_REF="${COMMON_CI_REF:-develop}"
    COMMON_CI_URL="https://gitlab.syncad.com/hive/common-ci-configuration/-/raw/${COMMON_CI_REF}"

    mkdir -p "$COMMON_CI_DIR/haf-app-tools/scripts"
    curl -fsSL "$COMMON_CI_URL/haf-app-tools/scripts/build_and_publish_instance.sh" \
        -o "$COMMON_SCRIPT"
    chmod +x "$COMMON_SCRIPT"
fi

exec "$COMMON_SCRIPT" --src-dir="$SRC_DIR" --project-name=hivemind "$@"
