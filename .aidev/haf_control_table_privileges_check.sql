-- Checks that the hivemind role, through any role it is a member of, holds none of
-- TRUNCATE, REFERENCES and TRIGGER on HAF's control tables. Row-level security keeps an
-- application to its own rows of these tables, but does not cover TRUNCATE; hive/haf#348
-- revoked the three from hive_applications_group. Needs a HAF that includes it.
--   psql -X -v ON_ERROR_STOP=1 -f .aidev/haf_control_table_privileges_check.sql
\set QUIET on

DO $$
DECLARE
    _held TEXT;
BEGIN
    SELECT string_agg(format('%s on hafd.%s', p.privilege, t.name), ', ' ORDER BY t.name, p.privilege) INTO _held
    FROM unnest(ARRAY['contexts', 'contexts_attachment', 'registered_tables', 'triggers',
                      'state_providers_registered', 'vacuum_requests', 'applications',
                      'application_dependencies']) t (name)
    CROSS JOIN unnest(ARRAY['TRUNCATE', 'REFERENCES', 'TRIGGER']) p (privilege)
    WHERE has_table_privilege('hivemind', format('hafd.%I', t.name), p.privilege);
    ASSERT _held IS NULL, format('the hivemind role holds %s', _held);
END
$$;

\echo 'HAF control tables: the hivemind role holds no TRUNCATE, REFERENCES or TRIGGER'
