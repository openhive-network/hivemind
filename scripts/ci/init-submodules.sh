#!/bin/bash
#
# Initialize all submodules for Hivemind CI
#
# Submodules initialized:
#   - reputation_tracker (no nested submodules)
#   - hafah (no nested submodules)
#   - tests/tests_api (no nested submodules)
#
# Note: HAF is no longer a submodule - we use pre-built images from the registry
# and fetch scripts from common-ci-configuration as needed.
#
set -euo pipefail

# Section markers for GitLab CI log folding
echo -e "\e[0Ksection_start:$(date +%s):init_submodules[collapsed=true]\r\e[0KInitializing submodules..."

git config --global --add safe.directory '*'

# Initialize reputation_tracker submodule
REPTRACKER_URL="https://gitlab.syncad.com/hive/reputation_tracker.git"
REPTRACKER_COMMIT=$(git ls-tree HEAD reputation_tracker | awk '{print $3}')
if [[ -n "$REPTRACKER_COMMIT" ]]; then
    echo "Initializing reputation_tracker submodule at commit $REPTRACKER_COMMIT"
    sudo rm -rf reputation_tracker 2>/dev/null || rm -rf reputation_tracker || true
    git clone --no-checkout "$REPTRACKER_URL" reputation_tracker
    cd reputation_tracker
    git checkout "$REPTRACKER_COMMIT"
    cd ..
else
    echo "Skipping reputation_tracker (not a submodule in this tree)"
fi

# Initialize hafah submodule
HAFAH_URL="https://gitlab.syncad.com/hive/HAfAH.git"
HAFAH_COMMIT=$(git ls-tree HEAD hafah | awk '{print $3}')
if [[ -n "$HAFAH_COMMIT" ]]; then
    echo "Initializing hafah submodule at commit $HAFAH_COMMIT"
    sudo rm -rf hafah 2>/dev/null || rm -rf hafah || true
    git clone --no-checkout "$HAFAH_URL" hafah
    cd hafah
    git checkout "$HAFAH_COMMIT" 2>/dev/null || {
        echo "Commit not in default branch, fetching all refs..."
        git fetch --all
        git checkout "$HAFAH_COMMIT"
    }
    cd ..
else
    echo "Skipping hafah (not a submodule in this tree)"
fi

# Initialize tests_api submodule
TESTS_API_URL="https://gitlab.syncad.com/hive/tests_api.git"
TESTS_API_COMMIT=$(git ls-tree HEAD tests/tests_api | awk '{print $3}')
if [[ -n "$TESTS_API_COMMIT" ]]; then
    echo "Initializing tests_api submodule at commit $TESTS_API_COMMIT"
    sudo rm -rf tests/tests_api 2>/dev/null || rm -rf tests/tests_api || true
    git clone --no-checkout "$TESTS_API_URL" tests/tests_api
    cd tests/tests_api
    git checkout "$TESTS_API_COMMIT"
    cd ../..
else
    echo "Skipping tests_api (not a submodule in this tree)"
fi

echo -e "\e[0Ksection_end:$(date +%s):init_submodules\r\e[0K"
echo "All submodules initialized successfully"
