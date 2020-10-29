#!/bin/bash

# $1 - server address
# $2 - server port
# $3 - path to test directory
# $4 - name of the benchmark script file

set -e

echo "=========================  BENCHMARKS  ================================="
echo "Server address: $1"
echo "Server port: $2"
echo "Test directory to be processed: $3"
echo "Benchmark test file name: $4.py"

BASE_DIR=$(pwd)
echo "Script base dir is: $BASE_DIR"

python3 -m pip install tox
export HIVEMIND_ADDRESS=$1
export HIVEMIND_PORT=$2
export BENCHMARKS_TESTS_PATH=$3
export BENCHMARKS_SCRIPT_NAME=$4
tox -e benchmark
