#!/bin/bash
# $1 = noindex|bm25
psql() { docker exec -i pg461 psql -U postgres -X -q "$@"; }
psql -c "DROP TABLE IF EXISTS post_data; CREATE TABLE post_data (id int PRIMARY KEY, title varchar(512), body text); CHECKPOINT;"
if [ "$1" = bm25 ]; then
  psql -c "CREATE INDEX post_data_bm25_idx ON post_data USING bm25 (id, title, body) WITH (key_field = 'id', text_fields = '{\"title\": {\"record\": \"position\"}, \"body\": {\"record\": \"position\"}}') WHERE is_top(id)"
fi
start=$(date +%s.%N)
for b in $(seq 0 19); do
  psql -c "INSERT INTO post_data SELECT * FROM src WHERE id > $((b*50000)) AND id <= $(((b+1)*50000))"
done
end=$(date +%s.%N)
echo "$1 inserts: $(echo "$end - $start" | bc) s"
if [ "$1" = noindex ]; then
  start=$(date +%s.%N)
  psql -c "CREATE INDEX post_data_bm25_idx ON post_data USING bm25 (id, title, body) WITH (key_field = 'id', text_fields = '{\"title\": {\"record\": \"position\"}, \"body\": {\"record\": \"position\"}}') WHERE is_top(id)"
  end=$(date +%s.%N)
  echo "build after: $(echo "$end - $start" | bc) s"
fi
psql -Atc "SELECT pg_size_pretty(pg_relation_size('post_data_bm25_idx'))"
