#!/bin/bash 

set -e

# Usage ci_stop_server.sh pid_file_name

if [ -f $1 ]; then
  PID=`cat $1`;
  kill -SIGINT $PID || true;
  sleep 5
  kill -9 $PID || true;
else
  echo Specified pid file: $1 does not exists.;
fi


