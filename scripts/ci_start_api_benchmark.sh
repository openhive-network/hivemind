#!/bin/bash

# $1 - server address
# $2 - server port
# $3 - path to test directory
# $4 - name of the benchmark script file
# $5 - path to generated junit xml file


set -e

echo "=========================  BENCHMARKS  ================================="
echo "Server address: $1"
echo "Server port: $2"
echo "Test directory to be processed: $3"
echo "Benchmark test file path and name: $4"
echo "junit xml file used to generate html with: $5"

BASE_DIR=$(pwd)
echo "Script base dir is: $BASE_DIR"

pip3 install tox --user

echo "Creating benchmark test file as: $4"
$BASE_DIR/tests/tests_api/hivemind/benchmarks/benchmark_generator.py $3 $4 "http://$1:$2"
echo "Running benchmark tests on http://$1:$2"
tox -e benchmark -- $4
echo "Creating html report..."
$BASE_DIR/scripts/xml_report_parser.py $3 $5