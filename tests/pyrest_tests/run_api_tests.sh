#!/bin/bash

NODE='http://127.0.0.1'
RPC_PORT=8080
EXIT_CODE=0
COMPARATOR=''

if [ $1 == 'equal' ]
then
   COMPARATOR='comparator_equal'
elif [ $1 == 'contain' ]
then
   COMPARATOR='comparator_contain'
else
   echo FATAL: $1 is not a valid comparator! && exit -1
fi

echo COMPARATOR: $COMPARATOR
echo "Running API tests\n"
pyresttest $NODE:$RPC_PORT ./basic_smoketest.yaml
[ $? -ne 0 ] && echo FATAL: hivemind not running? && exit -1

pyresttest $NODE:$RPC_PORT ./bridge_api/bridge_api_test.yaml --import_extensions='validator_ex;'$COMPARATOR
[ $? -ne 0 ] && EXIT_CODE=-1

pyresttest $NODE:$RPC_PORT ./condenser_api/condenser_api_test.yaml --import_extensions='validator_ex;'$COMPARATOR
[ $? -ne 0 ] && EXIT_CODE=-1

pyresttest $NODE:$RPC_PORT ./database_api/database_api_test.yaml --import_extensions='validator_ex;'$COMPARATOR
[ $? -ne 0 ] && EXIT_CODE=-1

pyresttest $NODE:$RPC_PORT ./follow_api/follow_api_test.yaml --import_extensions='validator_ex;'$COMPARATOR
[ $? -ne 0 ] && EXIT_CODE=-1

pyresttest $NODE:$RPC_PORT ./hive_api/hive_api_test.yaml --import_extensions='validator_ex;'$COMPARATOR
[ $? -ne 0 ] && EXIT_CODE=-1

pyresttest $NODE:$RPC_PORT ./tags_api/tags_api_test.yaml --import_extensions='validator_ex;'$COMPARATOR
[ $? -ne 0 ] && EXIT_CODE=-1
echo "Done!\n"

echo "Running API benchmark tests\n"
pyresttest $NODE:$RPC_PORT ./bridge_api/bridge_api_benchmark.yaml --import_extensions='validator_ex;'$COMPARATOR
[ $? -ne 0 ] && EXIT_CODE=-1

pyresttest $NODE:$RPC_PORT ./condenser_api/condenser_api_benchmark.yaml --import_extensions='validator_ex;'$COMPARATOR
[ $? -ne 0 ] && EXIT_CODE=-1

pyresttest $NODE:$RPC_PORT ./database_api/database_api_benchmark.yaml --import_extensions='validator_ex;'$COMPARATOR
[ $? -ne 0 ] && EXIT_CODE=-1

pyresttest $NODE:$RPC_PORT ./follow_api/follow_api_benchmark.yaml --import_extensions='validator_ex;'$COMPARATOR
[ $? -ne 0 ] && EXIT_CODE=-1

pyresttest $NODE:$RPC_PORT ./hive_api/hive_api_benchmark.yaml --import_extensions='validator_ex;'$COMPARATOR
[ $? -ne 0 ] && EXIT_CODE=-1

pyresttest $NODE:$RPC_PORT ./tags_api/tags_api_benchmark.yaml --import_extensions='validator_ex;'$COMPARATOR
[ $? -ne 0 ] && EXIT_CODE=-1
echo "Done!\n"

exit $EXIT_CODE
