#!/bin/bash
# aidev hivemind#472: stop the profiling clone's sync once the batch ending at $1 is logged
until docker logs --since 5m aidev472-hm-sync 2>&1 | grep -q "PHASE-SUMMARY\] blocks=[0-9]*-$1 "; do sleep 3; done
date -u +"%F %T stop requested"
docker stop -t 1800 aidev472-hm-sync
date -u +"%F %T stopped"
docker logs --tail 30 aidev472-hm-sync 2>&1 | grep -E "PHASE-SUMMARY|SIGINT|SIGTERM|batch queue" | tail -5
