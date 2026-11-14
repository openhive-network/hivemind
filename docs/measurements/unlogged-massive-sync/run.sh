#!/usr/bin/env bash
# run.sh MODE BATCHES: one LOGGED/UNLOGGED run, the votes workers and the posts worker concurrent.
# Expects a PostgreSQL 18 container named pg460 with a database bench; DISKS names the data devices.
set -euo pipefail
mode=$1; batches=$2; vb=${VB:-25000}; posts=${POSTS:-11400}; upd=${UPD:-20000}
P="docker exec -i pg460 psql -X -q -U postgres -d bench -v ON_ERROR_STOP=1"
QS="docker exec -i -e PGOPTIONS=-csynchronous_commit=off pg460 psql -X -At -U postgres -d bench"
Q="docker exec -i pg460 psql -X -At -U postgres -d bench"
pm=$mode; [ "$mode" = LOGGED ] && pm=""; $P -v mode="$pm" < "$(dirname "$0")/schema.sql"
$Q -c "CHECKPOINT"
sync; sleep 2
dw() { awk -v disks="${DISKS:-nvme0n1 nvme1n1}" 'index(" " disks " ", " " $3 " "){s+=$10} END{print s*512}' /proc/diskstats; }
snap() { $Q -c "select w.wal_records, w.wal_fpi, w.wal_bytes, w.wal_buffers_full, c.num_timed, c.num_requested, c.buffers_written, (select sum(write_bytes) from pg_stat_io) from pg_stat_wal w, pg_stat_checkpointer c"; }
s0=$(snap); d0=$(dw); t0=$(date +%s.%N)
for w in 0 1 2 3; do $QS -c "CALL votes_worker($w, 4, $batches, $vb)" >/dev/null & done
$QS -c "CALL posts_worker($batches, $posts, $upd)" >/dev/null &
wait
t1=$(date +%s.%N); s1=$(snap); d1=$(dw)
conv=0
if [ "$mode" = UNLOGGED ]; then
  c0=$(date +%s.%N)
  for t in hive_votes hive_post_data hive_posts hive_permlink_data; do ( ts=$(date +%s.%N); $Q -c "ALTER TABLE $t SET LOGGED" >/dev/null; echo "setlogged $t $(echo "$(date +%s.%N) - $ts" | bc)" ) & done
  wait
  conv=$(echo "$(date +%s.%N) - $c0" | bc)
fi
s2=$(snap); d2=$(dw)
sizes=$($Q -c "select string_agg(relname||'='||pg_table_size(oid)||'/'||pg_indexes_size(oid), ' ') from pg_class where relname in ('hive_votes','hive_posts','hive_post_data','hive_permlink_data')")
counts=$($Q -c "select (select count(*) from hive_votes), (select count(*) from hive_posts)")
echo "RESULT mode=$mode batches=$batches elapsed=$(echo "$t1 - $t0" | bc) conv=$conv disk_w_run=$((d1-d0)) disk_w_conv=$((d2-d1)) s0=$s0 s1=$s1 s2=$s2 counts=$counts sizes=$sizes"
