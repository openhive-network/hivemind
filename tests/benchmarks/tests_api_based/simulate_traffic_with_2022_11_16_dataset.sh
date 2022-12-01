#!/bin/bash
# This script setup and start benchmark test with request gathered from hivemind production (it tooks about 30 minutes)
# usage: ./simulate_traffic_with_2022_11_16_dataset.sh [ADDRESS = 'hive-6.pl.syncad.com:28080'] [PATH_TO_TESTS_API_BENCHMARKS_DIR = auto detect]
# WARNING: addres must be in format address:port, without proto or path

set -euo pipefail

function get_tests_api_benchmarks_dir {
    echo "`git -C $(dirname $1) rev-parse --show-toplevel`/tests/tests_api/benchmarks"
}

PATH_TO_TESTS_API_BENCHMARKS_DIR=${2:-`get_tests_api_benchmarks_dir $0`}
VENV_DIRECTORY_NAME=".venv"
VENV_DIRECTORY="$PATH_TO_TESTS_API_BENCHMARKS_DIR/$VENV_DIRECTORY_NAME"
BENCHMARK_SIGNATURE=`date "+%Y_%m_%dT%H_%M_%S"`
BENCHMARK_WORKDIR="benchmark_wdir_$BENCHMARK_SIGNATURE"
BENCHMARK_LOG_FILE="benchmark_output_$BENCHMARK_SIGNATURE.log"
ADDRESS_TO_TEST=${1:-'hive-6.pl.syncad.com:28080'}

pushd $PATH_TO_TESTS_API_BENCHMARKS_DIR

    PYTHON_VERION=`python --version | cut -d ' ' -f 2`
    PYTHON_VERSION_REGEX="3\.([89]|1[0-9])(\..+)?"
    if [[ ! $PYTHON_VERION =~ $PYTHON_VERSION_REGEX ]]; then
        echo "invalid python version, required 3.8+, but current is $PYTHON_VERION"
        exit 1
    fi

    if [ ! -d $VENV_DIRECTORY ]; then
        echo "creating virtual enviroment (`deactivate` to disable)"
        python -m venv $VENV_DIRECTORY_NAME
    fi

    echo "activating virtual enviroment"
    source $VENV_DIRECTORY/bin/activate

    echo "preparing python benchmarking enviroment"
    pip install --upgrade pip
    pip install -r "$PATH_TO_TESTS_API_BENCHMARKS_DIR/requirements.txt"

    echo "setting jmeter"
    $PATH_TO_TESTS_API_BENCHMARKS_DIR/setup_jmeter.bash
    source jmeter/activate
    echo "jmeter path: $JMETER"

    echo "starting benchmarks"
    python benchmark.py                              \
        -n universal                                 \
        -c 2022_11_16_hivemind_60M_prod_jrpc.csv     \
        -t 10                                        \
        -k 2000                                      \
        -a `echo $ADDRESS_TO_TEST | cut -d ':' -f 1` \
        -p `echo $ADDRESS_TO_TEST | cut -d ':' -f 2` \
        -j $JMETER                                   \
        -d $BENCHMARK_WORKDIR 2>&1 | tee -i $BENCHMARK_LOG_FILE

    echo "moving log output to benchmark working directory"
    mv "$BENCHMARK_LOG_FILE" "$BENCHMARK_WORKDIR/$BENCHMARK_LOG_FILE"

    echo "results of benchmarking are in $PATH_TO_TESTS_API_BENCHMARKS_DIR/$BENCHMARK_WORKDIR directory"

    echo "deactivating virtual enviroment"
    deactivate
popd
