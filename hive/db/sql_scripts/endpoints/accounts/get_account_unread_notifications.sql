/** openapi:paths
/accounts/{account-name}/notifications/unread:
  get:
    tags:
      - blog_api
    summary: Count an account''s unread notifications
    description: |
      Returns when the account last marked its notifications read and how many notifications of the
      last 90 days it has had since, the same object as `bridge.unread_notifications`.

      SQL example
      * `SELECT hivemind_endpoints.get_account_unread_notifications(''alice'');`

      REST call example
      * `GET ''https://%1$s/hivemind-api/accounts/alice/notifications/unread?min-score=25''`
    operationId: hivemind_endpoints.get_account_unread_notifications
    parameters:
      - in: path
        name: account-name
        required: true
        schema:
          type: string
        description: Account whose notifications are counted
      - in: query
        name: min-score
        required: false
        schema:
          type: integer
          default: NULL
        description: Minimum notification score, 0 to 100, 25 by default
    responses:
      '200':
        description: |
          The unread notification count

          * Returns `JSONB`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hivemind_endpoints.unread_notifications'
              x-sql-datatype: JSONB
      '400':
        description: Unknown account, or an invalid parameter
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hivemind_endpoints.get_account_unread_notifications;
CREATE OR REPLACE FUNCTION hivemind_endpoints.get_account_unread_notifications(
    "account-name" TEXT,
    "min-score" INT = NULL
)
RETURNS JSONB 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN hivemind_postgrest_utilities.rest_json_rpc_call('bridge', 'unread_notifications',
    jsonb_build_object('account', "account-name", 'min_score', "min-score"));
END
$$;
