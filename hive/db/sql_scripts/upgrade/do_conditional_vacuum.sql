SELECT COALESCE((SELECT hd.vacuum_needed FROM hivemind_app.hive_db_vacuum_needed hd WHERE hd.vacuum_needed LIMIT 1), False) AS needs_vacuum
\gset
\if :needs_vacuum
\qecho Running VACUUM on the database
VACUUM FULL VERBOSE ANALYZE;
\qecho Waiting 1 second...
SELECT pg_sleep(1);
SELECT relname, n_dead_tup AS n_dead_tup_now
,      n_live_tup AS n_live_tup_now
FROM pg_stat_user_tables
WHERE relname like 'hive_%';

\else
\qecho Skipping VACUUM on the database...
\endif

