CREATE EXTENSION IF NOT EXISTS pg_search;
SELECT extversion FROM pg_extension WHERE extname = 'pg_search';
CREATE OR REPLACE FUNCTION is_top(id int) RETURNS bool LANGUAGE sql IMMUTABLE AS 'SELECT id % 5 = 0';
DROP TABLE IF EXISTS words;
CREATE TABLE words AS SELECT g AS n, substr(md5(g::text), 1, 3 + g % 7) AS w FROM generate_series(1, 50000) g;
DROP TABLE IF EXISTS src;
CREATE OR REPLACE FUNCTION mkt(a text[], seed bigint, cnt int) RETURNS text LANGUAGE plpgsql IMMUTABLE AS
$f$ DECLARE r text[] := '{}'; BEGIN FOR i IN 1..cnt LOOP r := r || a[1 + ((seed * 7919 + i * 104729) % 50000)::int]; END LOOP; RETURN array_to_string(r, ' '); END $f$;
CREATE UNLOGGED TABLE src AS SELECT g AS id, mkt(wa.a, g, 8) AS title, mkt(wa.a, g + 1, 150) AS body
  FROM (SELECT array_agg(w ORDER BY n) a FROM words) wa, generate_series(1, :rows) g;
SELECT pg_size_pretty(pg_total_relation_size('src')), count(*) FROM src;
