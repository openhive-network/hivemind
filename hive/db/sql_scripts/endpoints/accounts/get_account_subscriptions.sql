/** openapi:paths
/accounts/{account-name}/subscriptions:
  get:
    tags:
      - blog_api
    summary: Get the communities an account subscribes to
    description: |
      Returns the communities the account subscribes to, the same list as `bridge.list_all_subscriptions`:
      for each one its name, title, the account''s role and the account''s title in it, the
      communities where the account has the highest role first.

      SQL example
      * `SELECT hivemind_endpoints.get_account_subscriptions(''alice'');`

      REST call example
      * `GET ''https://%1$s/hivemind-api/accounts/alice/subscriptions''`
    operationId: hivemind_endpoints.get_account_subscriptions
    parameters:
      - in: path
        name: account-name
        required: true
        schema:
          type: string
        description: Account whose subscriptions are listed
    responses:
      '200':
        description: |
          The account''s subscriptions, as `[name, title, role, role title]`

          * Returns `SETOF JSONB`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hivemind_endpoints.array_of_string_tuple'
              x-sql-datatype: SETOF JSONB
      '400':
        description: Unknown account, or an invalid parameter
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hivemind_endpoints.get_account_subscriptions;
CREATE OR REPLACE FUNCTION hivemind_endpoints.get_account_subscriptions(
    "account-name" TEXT
)
RETURNS SETOF JSONB 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN QUERY SELECT * FROM hivemind_postgrest_utilities.rest_json_rpc_rows('bridge', 'list_all_subscriptions',
    jsonb_build_object('account', "account-name"));
END
$$;
