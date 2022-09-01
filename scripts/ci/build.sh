#! /bin/bash

set -euo pipefail 

SCRIPTDIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
SRCROOT="$SCRIPTDIR/../../"

python3 -m venv .hivemind-venv
source .hivemind-venv/bin/activate

python3 -m pip install -U pip setuptools wheel build
pip3 install pyyaml

# Do actual installation in the source directory
pushd "$SRCROOT"
pip3 install .
python3 -m build --wheel

popd 
