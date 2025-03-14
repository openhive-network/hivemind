GRANT USAGE ON SCHEMA hivemind_app to hivemind_user;
GRANT USAGE ON SCHEMA hivemind_endpoints to hivemind_user;
GRANT USAGE ON SCHEMA hivemind_postgrest_utilities to hivemind_user;

GRANT SELECT ON ALL TABLES IN SCHEMA hivemind_app TO hivemind_user;
GRANT SELECT ON ALL TABLES IN SCHEMA hivemind_endpoints TO hivemind_user;
GRANT SELECT ON ALL TABLES IN SCHEMA hivemind_postgrest_utilities TO hivemind_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA hivemind_app GRANT SELECT ON TABLES TO hivemind_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA hivemind_endpoints GRANT SELECT ON TABLES TO hivemind_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA hivemind_postgrest_utilities GRANT SELECT ON TABLES TO hivemind_user;
