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

pip install tox
pip install prettytable

echo "Creating benchmark test file as: $4.py"
$BASE_DIR/tests/tests_api/hivemind/benchmarks/benchmark_generator.py $3 "$4.py" "http://$1:$2"
echo "Running benchmark tests on http://$1:$2"
tox -e benchmark -- --benchmark-json="$4.json" "$4.py"
echo "Creating html report from $4.json"
$BASE_DIR/scripts/json_report_parser.py $3 "$4.json"