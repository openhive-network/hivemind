#!/bin/bash

set -euo pipefail

JOB=$1

start() {
  mkdir -p ".tmp"
  echo `date +%s` > ".tmp/timer-start"
  echo "Timer: started at:" $(date -u +"%Y-%m-%dT%H:%M:%SZ")
}

check() {
    echo "Timer: current time:" $(date -u +"%Y-%m-%dT%H:%M:%SZ")
    start=$(cat ".tmp/timer-start" 2>/dev/null || echo 0)
    end=`date +%s`
    if [ "$start" -gt "0" ]; then
        runtime=$((end-start))
        echo "Timer: time elapsed: ${runtime} s"
    fi
}

main() {
  if [ "$JOB" = "start" ]; then
    start
  elif [ "$JOB" = "check" ]; then
    check
  else
    echo "Invalid argument"
    exit 1
  fi
}

main
