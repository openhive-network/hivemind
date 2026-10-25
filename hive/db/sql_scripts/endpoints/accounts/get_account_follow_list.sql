/** openapi:paths
/accounts/{account-name}/follow-lists/{type}:
  get:
    tags:
      - blog_api
    summary: Get one of an account''s follow lists
    description: |
      Returns one of the account''s lists, the same list as `bridge.get_follow_list` with the account
      as `observer`, in alphabetical order:
      * `blacklisted`: the accounts it blacklists;
      * `muted`: the accounts it mutes;
      * `follow_blacklist`: the accounts whose blacklists it follows, with their list descriptions;
      * `follow_muted`: the accounts whose mute lists it follows, with their list descriptions.

      SQL example
      * `SELECT hivemind_endpoints.get_account_follow_list(''alice'', ''muted'');`

      REST call example
      * `GET ''https://%1$s/hivemind-api/accounts/alice/follow-lists/muted''`
    operationId: hivemind_endpoints.get_account_follow_list
    parameters:
      - in: path
        name: account-name
        required: true
        schema:
          type: string
        description: Account whose list is returned
      - in: path
        name: type
        required: true
        schema:
          type: string
        description: '`blacklisted`, `muted`, `follow_blacklist` or `follow_muted`'
    responses:
      '200':
        description: |
          Accounts of the list

          * Returns `SETOF JSONB`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hivemind_endpoints.array_of_follow_list_entry'
              x-sql-datatype: SETOF JSONB
      '400':
        description: Unknown account, unsupported type, or an invalid parameter
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hivemind_endpoints.get_account_follow_list;
CREATE OR REPLACE FUNCTION hivemind_endpoints.get_account_follow_list(
    "account-name" TEXT,
    "type" TEXT
)
RETURNS SETOF JSONB 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN QUERY SELECT * FROM hivemind_postgrest_utilities.rest_json_rpc_rows('bridge', 'get_follow_list',
    jsonb_build_object('observer', "account-name", 'follow_type', "type"));
END
$$;
