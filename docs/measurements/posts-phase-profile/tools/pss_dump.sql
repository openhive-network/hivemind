\pset format unaligned
\pset tuples_only on
\pset fieldsep '\t'
select now(), (select current_block_num from hafd.contexts where name='hivemind_app'), s.queryid, s.toplevel, s.calls, s.total_exec_time, s.rows, s.shared_blks_hit, s.shared_blks_read, s.shared_blks_dirtied, s.shared_blks_written, s.wal_records, s.wal_fpi, s.wal_bytes, s.shared_blk_read_time, s.temp_blks_written, md5(s.query)
from pg_stat_statements s join pg_roles r on r.oid=s.userid where r.rolname='hivemind' and s.total_exec_time > 1;
