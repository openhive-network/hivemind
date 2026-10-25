/** openapi:paths
/accounts/{account-name}/follows-any-lists:
  get:
    tags:
      - blog_api
    summary: Tell whether an account follows any blacklist
    description: |
      Returns `true` when the account follows the blacklist of some account, otherwise `false`,
      the same value as `bridge.does_user_follow_any_lists` with the account as `observer`.

      SQL example
      * `SELECT hivemind_endpoints.get_account_follows_any_lists(''alice'');`

      REST call example
      * `GET ''https://%1$s/hivemind-api/accounts/alice/follows-any-lists''`
    operationId: hivemind_endpoints.get_account_follows_any_lists
    parameters:
      - in: path
        name: account-name
        required: true
        schema:
          type: string
        description: Account to check
    responses:
      '200':
        description: |
          Whether the account follows any blacklist

          * Returns `JSONB`
        content:
          application/json:
            schema:
              type: boolean
              x-sql-datatype: JSONB
      '400':
        description: Unknown account, or an invalid parameter
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hivemind_endpoints.get_account_follows_any_lists;
CREATE OR REPLACE FUNCTION hivemind_endpoints.get_account_follows_any_lists(
    "account-name" TEXT
)
RETURNS JSONB 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN hivemind_postgrest_utilities.rest_json_rpc_call('bridge', 'does_user_follow_any_lists',
    jsonb_build_object('observer', "account-name"));
END
$$;
