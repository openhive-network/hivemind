#!/bin/bash
#
# Initialize all submodules for Hivemind CI
#
# This script handles the complex submodule structure with nested HAF submodules
# that have relative URLs that don't work with GIT_SUBMODULE_STRATEGY: recursive.
#
# Submodules initialized:
#   - haf (with recursive for nested hive submodule)
#   - reputation_tracker (with nested haf, using absolute URL)
#   - hafah (with nested haf, using absolute URL)
#   - tests/tests_api (no nested submodules)
#
set -euo pipefail

# Section markers for GitLab CI log folding
echo -e "\e[0Ksection_start:$(date +%s):init_submodules[collapsed=true]\r\e[0KInitializing submodules..."

git config --global --add safe.directory '*'

HAF_URL="https://gitlab.syncad.com/hive/haf.git"

# Initialize HAF submodule (with nested hive submodule)
HAF_SUBMOD_COMMIT=$(git ls-tree HEAD haf | awk '{print $3}')
if [[ -z "$HAF_SUBMOD_COMMIT" ]]; then
    echo "ERROR: Could not determine haf submodule commit"
    exit 1
fi
echo "Initializing haf submodule at commit $HAF_SUBMOD_COMMIT"
sudo rm -rf haf 2>/dev/null || rm -rf haf || true
git clone --no-checkout "$HAF_URL" haf
cd haf
git fetch origin develop
git checkout "$HAF_SUBMOD_COMMIT"
git submodule update --init --recursive --jobs 4
cd ..

# Initialize reputation_tracker submodule with nested haf
REPTRACKER_URL="https://gitlab.syncad.com/hive/reputation_tracker.git"
REPTRACKER_COMMIT=$(git ls-tree HEAD reputation_tracker | awk '{print $3}')
if [[ -n "$REPTRACKER_COMMIT" ]]; then
    echo "Initializing reputation_tracker submodule at commit $REPTRACKER_COMMIT"
    sudo rm -rf reputation_tracker 2>/dev/null || rm -rf reputation_tracker || true
    git clone --no-checkout "$REPTRACKER_URL" reputation_tracker
    cd reputation_tracker
    git checkout "$REPTRACKER_COMMIT"
    # Initialize nested haf submodule (using absolute URL since relative ../haf.git won't work)
    NESTED_HAF_COMMIT=$(git ls-tree HEAD haf | awk '{print $3}')
    if [[ -n "$NESTED_HAF_COMMIT" ]]; then
        rm -rf haf
        git clone --no-checkout "$HAF_URL" haf
        cd haf
        git checkout "$NESTED_HAF_COMMIT"
        git submodule update --init --recursive --jobs 4
        cd ..
    fi
    cd ..
else
    echo "Skipping reputation_tracker (not a submodule in this tree)"
fi

# Initialize hafah submodule with nested haf
HAFAH_URL="https://gitlab.syncad.com/hive/HAfAH.git"
HAFAH_COMMIT=$(git ls-tree HEAD hafah | awk '{print $3}')
if [[ -n "$HAFAH_COMMIT" ]]; then
    echo "Initializing hafah submodule at commit $HAFAH_COMMIT"
    sudo rm -rf hafah 2>/dev/null || rm -rf hafah || true
    git clone --no-checkout "$HAFAH_URL" hafah
    cd hafah
    git checkout "$HAFAH_COMMIT"
    # Initialize nested haf submodule (using absolute URL since relative ../haf.git won't work)
    NESTED_HAF_COMMIT=$(git ls-tree HEAD haf | awk '{print $3}')
    if [[ -n "$NESTED_HAF_COMMIT" ]]; then
        rm -rf haf
        git clone --no-checkout "$HAF_URL" haf
        cd haf
        git checkout "$NESTED_HAF_COMMIT"
        git submodule update --init --recursive --jobs 4
        cd ..
    fi
    cd ..
else
    echo "Skipping hafah (not a submodule in this tree)"
fi

# Initialize tests_api submodule (no nested submodules)
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
