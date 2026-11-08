-- Checks that the installed hivemind is registered in HAF's application registry under
-- its lock name 'hivemind' (HAF's lock helpers find the row by that name), holding the
-- hivemind_app context and the completed-block function, and that no row is named after
-- the context. Needs a HAF with the registry (hive/haf#341).
--   psql -X -v ON_ERROR_STOP=1 -f .aidev/app_registry_check.sql
\set QUIET on

DO $$
DECLARE
    _app hafd.applications%ROWTYPE;
BEGIN
    SELECT * INTO _app FROM hafd.applications WHERE name = 'hivemind';
    ASSERT FOUND, 'no application registered as hivemind';
    ASSERT _app.contexts = ARRAY['hivemind_app'],
        format('application hivemind holds contexts %s, expected {hivemind_app}', _app.contexts);
    ASSERT _app.process_procedure IS NULL,
        format('application hivemind has process procedure %s, expected none', _app.process_procedure);
    ASSERT _app.completed_block_function = 'hivemind_app.completed_block_num',
        format('application hivemind has completed-block function %s', _app.completed_block_function);
    ASSERT NOT EXISTS ( SELECT 1 FROM hafd.applications WHERE name = 'hivemind_app' ),
        'an application is still registered as hivemind_app';
END
$$;

\echo 'HAF application registry: hivemind_app context registered as hivemind'
