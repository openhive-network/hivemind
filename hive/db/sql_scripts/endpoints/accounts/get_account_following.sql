/** openapi:paths
/accounts/{account-name}/following:
  get:
    tags:
      - blog_api
    summary: Get the accounts an account follows
    description: |
      Returns the accounts the account follows (or, with `type=ignore`, mutes), the same list as `condenser_api.get_following`,
      in alphabetical order.

      To fetch the next page pass the last account of the previous page as `start`.

      SQL example
      * `SELECT hivemind_endpoints.get_account_following(''alice'');`

      REST call example
      * `GET ''https://%1$s/hivemind-api/accounts/alice/following?type=blog&limit=100''`
    operationId: hivemind_endpoints.get_account_following
    parameters:
      - in: path
        name: account-name
        required: true
        schema:
          type: string
        description: Account whose following are listed
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
DROP FUNCTION IF EXISTS hivemind_endpoints.get_account_following;
CREATE OR REPLACE FUNCTION hivemind_endpoints.get_account_following(
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
  RETURN QUERY SELECT * FROM hivemind_postgrest_utilities.rest_json_rpc_rows('condenser_api', 'get_following',
    jsonb_build_object('account', "account-name", 'start', "start", 'follow_type', "type", 'limit', hivemind_postgrest_utilities.rest_page_limit("limit", 1000)));
END
$$;
