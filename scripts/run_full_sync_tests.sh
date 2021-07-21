#!/bin/bash

# script to run tavern tests for full sync hivemind node

export TAVERN_DIR="tests/api_tests/hivemind/tavern_full_sync"

SCRIPT=$(readlink -f "$0")

$(dirname "$SCRIPT")/run_tests.sh "$@"
