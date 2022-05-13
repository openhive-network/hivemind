-- Configure database for monitoring by unprivileged user `pgwatch2`
-- using program https://github.com/cybertec-postgresql/pgwatch2/

-- Example run:
-- psql -p 5432 -U postgres -h 127.0.0.1 -d template_monitoring -f ./setup_monitoring.sql

SET client_encoding = 'UTF8';
SET client_min_messages = 'warning';


\echo Installing monitoring stuff for pghero

BEGIN;

CREATE SCHEMA IF NOT EXISTS pghero;
COMMENT ON SCHEMA pghero IS
    'Schema contains objects for monitoring https://github.com/ankane/pghero/';

CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA public;
COMMENT ON EXTENSION pg_stat_statements
    IS 'Track execution statistics of all SQL statements executed';

-- view queries
CREATE OR REPLACE FUNCTION pghero.pg_stat_activity() RETURNS SETOF pg_stat_activity AS
$$
  SELECT * FROM pg_catalog.pg_stat_activity;
$$ LANGUAGE sql VOLATILE SECURITY DEFINER;

CREATE OR REPLACE VIEW pghero.pg_stat_activity AS SELECT * FROM pghero.pg_stat_activity();

-- kill queries
CREATE OR REPLACE FUNCTION pghero.pg_terminate_backend(pid int) RETURNS boolean AS
$$
  SELECT * FROM pg_catalog.pg_terminate_backend(pid);
$$ LANGUAGE sql VOLATILE SECURITY DEFINER;

-- query stats
CREATE OR REPLACE FUNCTION pghero.pg_stat_statements() RETURNS SETOF pg_stat_statements AS
$$
  SELECT * FROM pg_stat_statements;
$$ LANGUAGE sql VOLATILE SECURITY DEFINER;

CREATE OR REPLACE VIEW pghero.pg_stat_statements AS SELECT * FROM pghero.pg_stat_statements();

-- query stats reset
CREATE OR REPLACE FUNCTION pghero.pg_stat_statements_reset() RETURNS void AS
$$
  SELECT public.pg_stat_statements_reset();
$$ LANGUAGE sql VOLATILE SECURITY DEFINER;

-- improved query stats reset for Postgres 12+ - delete for earlier versions
-- CREATE OR REPLACE FUNCTION pghero.pg_stat_statements_reset(userid oid, dbid oid, queryid bigint) RETURNS void AS
-- $$
--   SELECT public.pg_stat_statements_reset(userid, dbid, queryid);
-- $$ LANGUAGE sql VOLATILE SECURITY DEFINER;

-- suggested indexes
CREATE OR REPLACE FUNCTION pghero.pg_stats() RETURNS
TABLE(schemaname name, tablename name, attname name, null_frac real, avg_width integer, n_distinct real) AS
$$
  SELECT schemaname, tablename, attname, null_frac, avg_width, n_distinct FROM pg_catalog.pg_stats;
$$ LANGUAGE sql VOLATILE SECURITY DEFINER;

CREATE OR REPLACE VIEW pghero.pg_stats AS SELECT * FROM pghero.pg_stats();

GRANT USAGE ON SCHEMA pghero TO pg_monitor;

GRANT SELECT ON ALL TABLES IN SCHEMA pghero TO pg_monitor;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pghero TO pg_monitor;

COMMIT;
