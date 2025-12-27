#! /bin/bash

set -euo pipefail 

SCRIPTDIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
SRCROOT="$SCRIPTDIR/../../"

python3 -m venv .hivemind-venv
source .hivemind-venv/bin/activate

python3 -m pip install -U pip setuptools wheel build
pip3 install pyyaml

# generate version for reputation tracker
pushd "$SRCROOT/reputation_tracker"
./scripts/generate_version_sql.sh "$SRCROOT/reputation_tracker" "$SRCROOT/.git/modules/reputation_tracker"
popd

# generate version for hafah
pushd "$SRCROOT/hafah"
./scripts/generate_version_sql.bash "$SRCROOT/hafah" "$SRCROOT/.git/modules/hafah"
popd

# Do actual installation in the source directory
pushd "$SRCROOT"
git status
pip3 install .

# verify hivemind signals module loads correctly (uses stdlib threading, no compilation needed)
python3 -c 'from hive.signals import AtomicCounter'

python3 -m build --wheel

popd 

