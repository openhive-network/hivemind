\pset format unaligned
\pset tuples_only on
\pset fieldsep '\t'
select distinct md5(s.query), s.queryid, left(regexp_replace(s.query, '\s+', ' ', 'g'), 600) from pg_stat_statements s join pg_roles r on r.oid=s.userid where r.rolname='hivemind' and s.total_exec_time > 1;
