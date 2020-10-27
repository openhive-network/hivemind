-- Configure database for monitoring by unprivileged user `pgwatch2`
-- using program https://github.com/cybertec-postgresql/pgwatch2/

-- Example run:
-- psql -p 5432 -U postgres -h 127.0.0.1 -d template_monitoring -f ./setup_monitoring_pgwatch2.sql

SET client_encoding = 'UTF8';
SET client_min_messages = 'warning';


\echo Installing monitoring stuff for pgwatch2

BEGIN;

CREATE SCHEMA IF NOT EXISTS pgwatch2;
COMMENT ON SCHEMA pgwatch2 IS
    'Schema contains objects for monitoring https://github.com/cybertec-postgresql/pgwatch2';


CREATE EXTENSION IF NOT EXISTS plpython3u WITH SCHEMA pg_catalog;
COMMENT ON EXTENSION plpython3u IS 'PL/Python3U untrusted procedural language';

CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA public;
COMMENT ON EXTENSION pg_stat_statements
    IS 'Track execution statistics of all SQL statements executed';

CREATE EXTENSION IF NOT EXISTS pg_qualstats;
COMMENT ON EXTENSION pg_qualstats
    IS 'Statistics on predicates found in WHERE statements and JOIN clauses.';

CREATE FUNCTION pgwatch2.get_load_average(OUT load_1min double precision,
        OUT load_5min double precision, OUT load_15min double precision)
        RETURNS record
    LANGUAGE plpython3u SECURITY DEFINER
    AS $$
from os import getloadavg
la = getloadavg()
return [la[0], la[1], la[2]]
$$;


CREATE FUNCTION pgwatch2.get_psutil_cpu(OUT cpu_utilization double precision,
        OUT load_1m_norm double precision, OUT load_1m double precision,
        OUT load_5m_norm double precision, OUT load_5m double precision,
        OUT "user" double precision, OUT system double precision,
        OUT idle double precision, OUT iowait double precision,
        OUT irqs double precision, OUT other double precision) RETURNS record
    LANGUAGE plpython3u SECURITY DEFINER
    AS $$

from os import getloadavg
from psutil import cpu_times_percent, cpu_percent, cpu_count
from threading import Thread

class GetCpuPercentThread(Thread):
    def __init__(self, interval_seconds):
        self.interval_seconds = interval_seconds
        self.cpu_utilization_info = None
        super(GetCpuPercentThread, self).__init__()

    def run(self):
        self.cpu_utilization_info = cpu_percent(self.interval_seconds)

t = GetCpuPercentThread(0.5)
t.start()

ct = cpu_times_percent(0.5)
la = getloadavg()

t.join()

return t.cpu_utilization_info, la[0] / cpu_count(), la[0], \
    la[1] / cpu_count(), la[1], ct.user, ct.system, ct.idle, ct.iowait, \
    ct.irq + ct.softirq, ct.steal + ct.guest + ct.guest_nice

$$;


CREATE FUNCTION pgwatch2.get_psutil_disk(OUT dir_or_tablespace text,
        OUT path text, OUT total double precision, OUT used double precision,
        OUT free double precision, OUT percent double precision)
        RETURNS SETOF record
    LANGUAGE plpython3u SECURITY DEFINER
    AS $$

from os import stat
from os.path import join, exists
from psutil import disk_usage
ret_list = []

# data_directory
sqlstring = """select
    current_setting('data_directory') as dd,
    current_setting('log_directory') as ld,
    current_setting('server_version_num')::int as pgver"""
r = plpy.execute(sqlstring)
dd = r[0]['dd']
ld = r[0]['ld']
du_dd = disk_usage(dd)
ret_list.append(['data_directory', dd, du_dd.total, du_dd.used, du_dd.free,
    du_dd.percent])

dd_stat = stat(dd)
# log_directory
if ld:
    if not ld.startswith('/'):
        ld_path = join(dd, ld)
    else:
        ld_path = ld
    if exists(ld_path):
        log_stat = stat(ld_path)
        if log_stat.st_dev == dd_stat.st_dev:
            pass # no new info, same device
        else:
            du = disk_usage(ld_path)
            ret_list.append(['log_directory', ld_path, du.total, du.used,
                du.free, du.percent])

# WAL / XLOG directory
# plpy.notice('pg_wal' if r[0]['pgver'] >= 100000 else 'pg_xlog', r[0]['pgver'])
joined_path_wal = join(r[0]['dd'], 'pg_wal' if r[0]['pgver'] >= 100000 else 'pg_xlog')
wal_stat = stat(joined_path_wal)
if wal_stat.st_dev == dd_stat.st_dev:
    pass # no new info, same device
else:
    du = disk_usage(joined_path_wal)
    ret_list.append(['pg_wal', joined_path_wal, du.total, du.used, du.free,
        du.percent])

# add user created tablespaces if any
sql_tablespaces = """
    select spcname as name, pg_catalog.pg_tablespace_location(oid) as location
    from pg_catalog.pg_tablespace where not spcname like any(array[E'pg\\_%'])"""
for row in plpy.cursor(sql_tablespaces):
    du = disk_usage(row['location'])
    ret_list.append([row['name'], row['location'], du.total, du.used, du.free,
        du.percent])
return ret_list

$$;


CREATE FUNCTION pgwatch2.get_psutil_disk_io_total(
        OUT read_count double precision, OUT write_count double precision,
        OUT read_bytes double precision, OUT write_bytes double precision)
        RETURNS record
    LANGUAGE plpython3u SECURITY DEFINER
    AS $$
from psutil import disk_io_counters
dc = disk_io_counters(perdisk=False)
return dc.read_count, dc.write_count, dc.read_bytes, dc.write_bytes
$$;


CREATE FUNCTION pgwatch2.get_psutil_mem(OUT total double precision,
        OUT used double precision, OUT free double precision,
        OUT buff_cache double precision, OUT available double precision,
        OUT percent double precision, OUT swap_total double precision,
        OUT swap_used double precision, OUT swap_free double precision,
        OUT swap_percent double precision) RETURNS record
    LANGUAGE plpython3u SECURITY DEFINER
    AS $$
from psutil import virtual_memory, swap_memory
vm = virtual_memory()
sw = swap_memory()
return vm.total, vm.used, vm.free, vm.buffers + vm.cached, vm.available, \
    vm.percent, sw.total, sw.used, sw.free, sw.percent
$$;


CREATE FUNCTION pgwatch2.get_stat_activity() RETURNS SETOF pg_stat_activity
    LANGUAGE sql SECURITY DEFINER
    AS $$
  select * from pg_stat_activity
    where datname = current_database() and pid != pg_backend_pid()
$$;


CREATE FUNCTION pgwatch2.get_stat_replication()
        RETURNS SETOF pg_stat_replication
    LANGUAGE sql SECURITY DEFINER
    AS $$
  select * from pg_stat_replication
$$;


CREATE FUNCTION pgwatch2.get_stat_statements()
        RETURNS SETOF public.pg_stat_statements
    LANGUAGE sql SECURITY DEFINER
    AS $$
  select
    s.*
  from
    pg_stat_statements s
    join
    pg_database d
      on d.oid = s.dbid and d.datname = current_database()
$$;


CREATE FUNCTION pgwatch2.get_table_bloat_approx_sql(OUT full_table_name text,
        OUT approx_bloat_percent double precision,
        OUT approx_bloat_bytes double precision,
        OUT fillfactor integer) RETURNS SETOF record
    LANGUAGE sql SECURITY DEFINER
    AS $$

SELECT
    quote_ident(schemaname) || '.' || quote_ident(tblname) as full_table_name,
    bloat_ratio as approx_bloat_percent,
    bloat_size as approx_bloat_bytes,
    fillfactor
FROM
    (
        /* WARNING: executed with a non-superuser role, the query inspect only tables you are granted to read.
         * This query is compatible with PostgreSQL 9.0 and more
         */
        SELECT
            current_database(),
            schemaname,
            tblname,
            bs * tblpages AS real_size,
            (tblpages - est_tblpages) * bs AS extra_size,
            CASE
                WHEN tblpages - est_tblpages > 0
                    THEN 100 * (tblpages - est_tblpages) / tblpages :: float
                ELSE 0
            END AS extra_ratio,
            fillfactor,
            CASE
                WHEN tblpages - est_tblpages_ff > 0
                    THEN (tblpages - est_tblpages_ff) * bs
                ELSE 0
            END AS bloat_size,
            CASE
                WHEN tblpages - est_tblpages_ff > 0
                    THEN 100 * (tblpages - est_tblpages_ff) / tblpages :: float
                ELSE 0
            END AS bloat_ratio,
            is_na -- , (pst).free_percent + (pst).dead_tuple_percent AS real_frag
        FROM
            (
                SELECT
                    ceil(reltuples / ((bs - page_hdr) / tpl_size))
                        + ceil(toasttuples / 4) AS est_tblpages,
                    ceil(
                        reltuples / ((bs - page_hdr) * fillfactor
                            / (tpl_size * 100))
                    ) + ceil(toasttuples / 4) AS est_tblpages_ff,
                    tblpages,
                    fillfactor,
                    bs,
                    tblid,
                    schemaname,
                    tblname,
                    heappages,
                    toastpages,
                    is_na -- , stattuple.pgstattuple(tblid) AS pst
                FROM
                    (
                        SELECT
                            (
                                4 + tpl_hdr_size + tpl_data_size + (2 * ma) - CASE
                                    WHEN tpl_hdr_size % ma = 0 THEN ma
                                    ELSE tpl_hdr_size % ma
                                END - CASE
                                    WHEN ceil(tpl_data_size) :: int % ma = 0 THEN ma
                                    ELSE ceil(tpl_data_size) :: int % ma
                                END
                            ) AS tpl_size,
                            bs - page_hdr AS size_per_block,
                            (heappages + toastpages) AS tblpages,
                            heappages,
                            toastpages,
                            reltuples,
                            toasttuples,
                            bs,
                            page_hdr,
                            tblid,
                            schemaname,
                            tblname,
                            fillfactor,
                            is_na
                        FROM
                            (
                                SELECT
                                    tbl.oid AS tblid,
                                    ns.nspname AS schemaname,
                                    tbl.relname AS tblname,
                                    tbl.reltuples,
                                    tbl.relpages AS heappages,
                                    coalesce(toast.relpages, 0) AS toastpages,
                                    coalesce(toast.reltuples, 0) AS toasttuples,
                                    coalesce(
                                        substring(
                                            array_to_string(tbl.reloptions, ' ')
                                            FROM
                                                'fillfactor=([0-9]+)'
                                        ) :: smallint,
                                        100
                                    ) AS fillfactor,
                                    current_setting('block_size') :: numeric AS bs,
                                    CASE
                                        WHEN version() ~ 'mingw32'
                                            OR version() ~ '64-bit|x86_64|ppc64|ia64|amd64'
                                        THEN 8
                                        ELSE 4
                                    END AS ma,
                                    24 AS page_hdr,
                                    23 + CASE
                                        WHEN MAX(coalesce(null_frac, 0)) > 0
                                        THEN (7 + count(*)) / 8
                                        ELSE 0 :: int
                                    END + CASE
                                        WHEN tbl.relhasoids THEN 4
                                        ELSE 0
                                    END AS tpl_hdr_size,
                                    sum(
                                        (1 - coalesce(s.null_frac, 0)) * coalesce(s.avg_width, 1024)
                                    ) AS tpl_data_size,
                                    bool_or(att.atttypid = 'pg_catalog.name' :: regtype)
                                    OR count(att.attname) <> count(s.attname) AS is_na
                                FROM
                                    pg_attribute AS att
                                    JOIN pg_class AS tbl ON att.attrelid = tbl.oid
                                    JOIN pg_namespace AS ns ON ns.oid = tbl.relnamespace
                                    LEFT JOIN pg_stats AS s ON s.schemaname = ns.nspname
                                    AND s.tablename = tbl.relname
                                    AND s.inherited = false
                                    AND s.attname = att.attname
                                    LEFT JOIN pg_class AS toast ON tbl.reltoastrelid = toast.oid
                                WHERE
                                    att.attnum > 0
                                    AND NOT att.attisdropped
                                    AND tbl.relkind IN ('r', 'm')
                                    AND ns.nspname != 'information_schema'
                                GROUP BY
                                    1,
                                    2,
                                    3,
                                    4,
                                    5,
                                    6,
                                    7,
                                    8,
                                    9,
                                    10,
                                    tbl.relhasoids
                                ORDER BY
                                    2,
                                    3
                            ) AS s
                    ) AS s2
            ) AS s3 -- WHERE NOT is_na
    ) s4
$$;


CREATE FUNCTION pgwatch2.get_wal_size() RETURNS bigint
    LANGUAGE sql SECURITY DEFINER
    AS $$
select (sum((pg_stat_file('pg_wal/' || name)).size))::int8 from pg_ls_waldir()
$$;


GRANT USAGE ON SCHEMA pgwatch2 TO pg_monitor;

GRANT EXECUTE ON FUNCTION pgwatch2.get_load_average(
    OUT load_1min double precision, OUT load_5min double precision,
    OUT load_15min double precision) TO pg_monitor;

GRANT EXECUTE ON FUNCTION pgwatch2.get_psutil_cpu(
    OUT cpu_utilization double precision, OUT load_1m_norm double precision,
    OUT load_1m double precision, OUT load_5m_norm double precision,
    OUT load_5m double precision, OUT "user" double precision,
    OUT system double precision, OUT idle double precision,
    OUT iowait double precision, OUT irqs double precision,
    OUT other double precision) TO pg_monitor;

GRANT EXECUTE ON FUNCTION pgwatch2.get_psutil_disk(OUT dir_or_tablespace text,
    OUT path text, OUT total double precision, OUT used double precision,
    OUT free double precision, OUT percent double precision) TO pg_monitor;

GRANT EXECUTE ON FUNCTION pgwatch2.get_psutil_disk_io_total(
    OUT read_count double precision, OUT write_count double precision,
    OUT read_bytes double precision, OUT write_bytes double precision)
    TO pg_monitor;

GRANT EXECUTE ON FUNCTION pgwatch2.get_psutil_mem(OUT total double precision,
    OUT used double precision, OUT free double precision,
    OUT buff_cache double precision, OUT available double precision,
    OUT percent double precision, OUT swap_total double precision,
    OUT swap_used double precision, OUT swap_free double precision,
    OUT swap_percent double precision) TO pg_monitor;

GRANT EXECUTE ON FUNCTION pgwatch2.get_wal_size() TO pg_monitor;

GRANT SELECT ON TABLE pg_catalog.pg_subscription TO pg_monitor;


COMMIT;
