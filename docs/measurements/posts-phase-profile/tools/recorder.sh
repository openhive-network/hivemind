#!/bin/bash
# aidev hivemind#472: every 10 min append hivemind's pg_stat_statements and table sizes, then reset
cd ~/aidev472
P="docker exec -i -u postgres aidev472-haf psql -d haf_block_log -X -q"
while docker ps --format '{{.Names}}' | grep -q '^aidev472-hm-sync$'; do
  sleep 600
  $P < pss_dump.sql >> sync_pss.tsv
  $P < pss_queries.sql >> sync_queries.tsv
  $P < sizes.sql >> sync_sizes.tsv
  echo "select pg_stat_statements_reset();" | $P > /dev/null
done
