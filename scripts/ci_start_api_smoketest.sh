#!/bin/bash 

set -e

cd tests/
rm -rf ./build
mkdir ./build
cd build/
cmake -DTEST_NODE="$1" ../
ctest -R api/pyresttests/5000000 --output-on-failure
