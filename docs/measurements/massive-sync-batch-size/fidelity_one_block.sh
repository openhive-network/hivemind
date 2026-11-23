#!/bin/bash
# fidelity_one_block.sh LABEL SRC LIMIT SPLIT_BLOCK MAXBLOCK
# Sync at 10000 blocks per batch until the batch ending at SPLIT_BLOCK is in flight, kill it,
# then restart at LIMIT blocks per batch (--max-batch=LIMIT) up to MAXBLOCK: the restart replays
# that batch, then processes SPLIT_BLOCK+1..MAXBLOCK in batches of LIMIT (1: one block at a time).
# Natural-key and id dumps into logs/LABEL/, as fidelity_run.sh, which also documents NAME and
# SYNC_ARGS (passed to both syncs).
set -uo pipefail
label=$1; src=$2; limit=$3; split=$4; max=$5
name=${NAME:-hm477}
cd /scratch/$name
RT=registry.gitlab.syncad.com/hive/hivemind/aidev-tests@sha256:5e11cad742290640c091b2f054e7d2b4684fc406e6ad6af7c00e73b007074ac7
ds=scratch/$name-$label; mnt=/scratch/$name-$label; pg=$name-pg-$label; hv=$name-hive-$label
out=logs/$label; mkdir -p $out
docker rm -f $pg $hv >/dev/null 2>&1
sudo zfs destroy -r $ds 2>/dev/null
sudo zfs clone -o mountpoint=$mnt scratch/$name-base@installed $ds
bash pg.sh start $pg $mnt || exit 1
q() { docker exec $pg psql -h 127.0.0.1 -U haf_admin -d haf_block_log -XAtc "$1"; }
sync_once() {  # LIMIT MAXBLOCK [MAX_BATCH]
  docker run --rm --name $hv --network $name -e PYTHONPATH=/src -v /scratch/$name/$src:/src -w /src --entrypoint python3 $RT \
    -m hive.cli sync --database-url=postgresql://hivemind@$pg:5432/haf_block_log --reptracker-schema-name=reptracker_app \
    --test-max-block=$2 --massive-sync-batch-blocks=$1 ${3:+--max-batch=$3} --prometheus-port 11011 --test-profile=False \
    ${SYNC_ARGS:-} 2>&1 \
    | python3 -u -c 'import sys,time
for l in sys.stdin: sys.stdout.write(f"{time.time():.3f} {l}"); sys.stdout.flush()'
  return ${PIPESTATUS[0]}
}
sync_once 10000 4990000 > $out/sync.log 2>&1 & syncpid=$!
while sleep 0.5; do
  b=$(q "select coalesce((select current_block_num from hafd.contexts where name='hivemind_app'),0)" 2>/dev/null || echo 0)
  if [ "${b:-0}" -ge "$split" ]; then
    docker kill $hv >/dev/null
    echo "KILLED at context block $b, _batch_queue=$(q "select string_agg(first_block||'..'||last_block, ', ' order by first_block) from hivemind_app._batch_queue")" >> $out/sync.log
    break
  fi
done
wait $syncpid
t0=$(date +%s)
sync_once $limit $max $limit >> $out/sync.log 2>&1
rc=$?
echo "label=$label src=$src limit=$limit split=$split max=$max rc=$rc restart_wall_s=$(( $(date +%s) - t0 ))" > $out/result
docker cp fidelity_dump.sql $pg:/tmp/dump.sql
docker exec -w /tmp $pg bash -c "psql -h 127.0.0.1 -U haf_admin -d haf_block_log -XAtq -F '	' -f /tmp/dump.sql" >> $out/result 2>&1
for f in posts votes notifs mentions postdata post_ids notif_ids accounts follows muted blacklisted follow_muted \
         follow_blacklisted reblogs feed_cache counts; do docker cp $pg:/tmp/$f.txt $out/$f.txt; done
bash pg.sh stop $pg
sudo zfs destroy -r $ds
echo "RUN_DONE $label rc=$rc"
