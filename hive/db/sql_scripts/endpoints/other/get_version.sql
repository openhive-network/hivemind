/** openapi:paths
/version:
  get:
    tags:
      - Other
    summary: Get hivemind''s version
    description: |
      Get the version and git revision of the running hivemind, together with
      the database schema version (patch level). The fields match the ones
      returned by the JSON-RPC `hive.get_info` call.

      SQL example
      * `SELECT hivemind_endpoints.get_version();`

      REST call example
      * `GET ''https://%1$s/hivemind-api/version''`
    operationId: hivemind_endpoints.get_version
    responses:
      '200':
        description: |
          Hivemind version information.

          * Returns `JSON`
        content:
          application/json:
            schema:
              type: object
              x-sql-datatype: JSON
              properties:
                hivemind_version:
                  type: string
                  description: hivemind package version
                hivemind_git_rev:
                  type: string
                  description: git commit hash hivemind was built from
                hivemind_git_date:
                  type: string
                  format: date-time
                  description: date of that git commit
                database_schema_version:
                  type: integer
                  description: database schema patch level
            example:
              hivemind_version: 1.28.8
              hivemind_git_rev: 455898cc3462d4e5ee2274756e5e3d44688fe204
              hivemind_git_date: '2026-10-01T12:00:00'
              database_schema_version: 42
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hivemind_endpoints.get_version;
CREATE OR REPLACE FUNCTION hivemind_endpoints.get_version()
RETURNS JSON 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  -- Short cache - the version changes when hivemind is upgraded or redeployed
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

  RETURN (
    SELECT json_build_object(
      'hivemind_version', hs.hivemind_version,
      'hivemind_git_rev', hs.hivemind_git_rev,
      'hivemind_git_date', hs.hivemind_git_date,
      'database_schema_version', (SELECT MAX(level) FROM hivemind_app.hive_db_patch_level)
    )
    FROM hivemind_app.hive_state hs
    LIMIT 1
  );
END
$$;
