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

# immediately initialize atomic package to avoid spawning compiler at final image
python3 -c 'import atomic'

python3 -m build --wheel

popd 

