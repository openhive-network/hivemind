#!/bin/bash

NODE='http://127.0.0.1'
RPC_PORT=8080
EXIT_CODE=0

echo "Running API benchmark tests\n"
pyresttest $NODE:$RPC_PORT ./bridge/bridge_api_benchmark.yaml
[ $? -ne 0 ] && EXIT_CODE=-1

pyresttest $NODE:$RPC_PORT ./condenser_api/condenser_api_benchmark.yaml
[ $? -ne 0 ] && EXIT_CODE=-1

pyresttest $NODE:$RPC_PORT ./database_api/database_api_benchmark.yaml
[ $? -ne 0 ] && EXIT_CODE=-1

pyresttest $NODE:$RPC_PORT ./follow_api/follow_api_benchmark.yaml
[ $? -ne 0 ] && EXIT_CODE=-1

pyresttest $NODE:$RPC_PORT ./hive_api/hive_api_benchmark.yaml
[ $? -ne 0 ] && EXIT_CODE=-1

pyresttest $NODE:$RPC_PORT ./tags_api/tags_api_benchmark.yaml
[ $? -ne 0 ] && EXIT_CODE=-1
echo "Done!\n"

exit $EXIT_CODE