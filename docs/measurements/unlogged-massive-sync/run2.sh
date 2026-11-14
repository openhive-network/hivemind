#!/usr/bin/env bash
# run2.sh MODE BATCHES — like run.sh, but the votes phase (4 workers) and the posts phase
# (1 connection) run one after the other, as in a hivemind batch, each timed with its WAL.
set -euo pipefail
mode=$1; batches=$2; vb=${VB:-25000}; posts=${POSTS:-11400}; upd=${UPD:-20000}
QS="docker exec -i -e PGOPTIONS=-csynchronous_commit=off pg460 psql -X -At -U postgres -d bench"
Q="docker exec -i pg460 psql -X -At -U postgres -d bench"
P="docker exec -i pg460 psql -X -q -U postgres -d bench -v ON_ERROR_STOP=1"
pm=$mode; [ "$mode" = LOGGED ] && pm=""; $P -v mode="$pm" < "$(dirname "$0")/schema.sql"
$Q -c "CHECKPOINT" >/dev/null; sync; sleep 2
dw() { awk -v disks="${DISKS:-nvme0n1 nvme1n1}" 'index(" " disks " ", " " $3 " "){s+=$10} END{print s*512}' /proc/diskstats; }
snap() { $Q -c "select w.wal_bytes||'|'||c.num_requested||'|'||c.buffers_written from pg_stat_wal w, pg_stat_checkpointer c"; }
now() { date +%s.%N; }
s0=$(snap); d0=$(dw); t0=$(now)
for w in 0 1 2 3; do $QS -c "CALL votes_worker($w, 4, $batches, $vb)" >/dev/null & done
wait
t1=$(now); s1=$(snap); d1=$(dw)
$QS -c "CALL posts_worker($batches, $posts, $upd)" >/dev/null
t2=$(now); s2=$(snap); d2=$(dw)
conv=0
if [ "$mode" = UNLOGGED ]; then
  for t in hive_votes hive_post_data hive_posts hive_permlink_data; do ( ts=$(now); $Q -c "ALTER TABLE $t SET LOGGED" >/dev/null; echo "setlogged $t $(echo "$(now) - $ts" | bc)" ) & done
  wait
  conv=$(echo "$(now) - $t2" | bc)
fi
s3=$(snap); d3=$(dw)
echo "RESULT2 mode=$mode votes_s=$(echo "$t1 - $t0" | bc) posts_s=$(echo "$t2 - $t1" | bc) conv=$conv disk=$((d1-d0))/$((d2-d1))/$((d3-d2)) wal_ckpt_buf: s0=$s0 s1=$s1 s2=$s2 s3=$s3"
