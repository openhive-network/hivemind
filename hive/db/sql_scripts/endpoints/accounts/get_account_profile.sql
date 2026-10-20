/** openapi:paths
/accounts/{account-name}/profile:
  get:
    tags:
      - blog_api
    summary: Get an account''s profile
    description: |
      Returns the account''s profile, the same object as `bridge.get_profile`.

      SQL example
      * `SELECT hivemind_endpoints.get_account_profile(''alice'');`

      REST call example
      * `GET ''https://%1$s/hivemind-api/accounts/alice/profile''`
    operationId: hivemind_endpoints.get_account_profile
    parameters:
      - in: path
        name: account-name
        required: true
        schema:
          type: string
        description: Account whose profile is returned
      - in: query
        name: observer
        required: false
        schema:
          type: string
          default: NULL
        description: |
          Account whose relationship to the profiled account is reported in `context`. The response
          without an observer is the one meant for caching.
    responses:
      '200':
        description: |
          The account''s profile

          * Returns `JSONB`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hivemind_endpoints.bridge_profile'
              x-sql-datatype: JSONB
      '400':
        description: Unknown account or an invalid parameter
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hivemind_endpoints.get_account_profile;
CREATE OR REPLACE FUNCTION hivemind_endpoints.get_account_profile(
    "account-name" TEXT,
    "observer" TEXT = NULL
)
RETURNS JSONB 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN hivemind_postgrest_utilities.rest_json_rpc_call('bridge', 'get_profile',
    jsonb_build_object('account', "account-name", 'observer', "observer"));
END
$$;
