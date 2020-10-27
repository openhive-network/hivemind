#!/bin/bash

set -euo pipefail

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

"$1"
