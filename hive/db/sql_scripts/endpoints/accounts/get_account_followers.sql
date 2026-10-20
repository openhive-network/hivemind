/** openapi:paths
/accounts/{account-name}/followers:
  get:
    tags:
      - blog_api
    summary: Get an account''s followers
    description: |
      Returns the accounts that follow (or, with `type=ignore`, mute) the account, the same list as `condenser_api.get_followers`,
      in alphabetical order.

      To fetch the next page pass the last account of the previous page as `start`.

      SQL example
      * `SELECT hivemind_endpoints.get_account_followers(''alice'');`

      REST call example
      * `GET ''https://%1$s/hivemind-api/accounts/alice/followers?type=blog&limit=100''`
    operationId: hivemind_endpoints.get_account_followers
    parameters:
      - in: path
        name: account-name
        required: true
        schema:
          type: string
        description: Account whose followers are listed
      - in: query
        name: type
        required: false
        schema:
          type: string
          default: NULL
        description: '`blog` (follows, the default) or `ignore` (mutes)'
      - in: query
        name: limit
        required: false
        schema:
          type: integer
          default: NULL
        description: Maximum number of accounts to return, at most 1000 (the default)
      - in: query
        name: start
        required: false
        schema:
          type: string
          default: NULL
        description: Last account of the previous page
    responses:
      '200':
        description: |
          Follow relations

          * Returns `SETOF JSONB`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hivemind_endpoints.array_of_follow'
              x-sql-datatype: SETOF JSONB
      '400':
        description: Unknown account or start account, unsupported type, or an invalid parameter
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hivemind_endpoints.get_account_followers;
CREATE OR REPLACE FUNCTION hivemind_endpoints.get_account_followers(
    "account-name" TEXT,
    "type" TEXT = NULL,
    "limit" INT = NULL,
    "start" TEXT = NULL
)
RETURNS SETOF JSONB 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN QUERY SELECT * FROM hivemind_postgrest_utilities.rest_json_rpc_rows('condenser_api', 'get_followers',
    jsonb_build_object('account', "account-name", 'start', "start", 'follow_type', "type", 'limit', hivemind_postgrest_utilities.rest_page_limit("limit", 1000)));
END
$$;
