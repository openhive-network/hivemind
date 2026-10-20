/** openapi:paths
/accounts/{account-name}/notifications:
  get:
    tags:
      - blog_api
    summary: Get an account''s notifications
    description: |
      Returns the account''s notifications of the last 90 days, newest first, the same list as
      `bridge.account_notifications`.

      To fetch the next page pass the `id` of the last notification of the previous page as `last-id`.

      SQL example
      * `SELECT hivemind_endpoints.get_account_notifications(''alice'');`

      REST call example
      * `GET ''https://%1$s/hivemind-api/accounts/alice/notifications?type=reply,mention&limit=50''`
    operationId: hivemind_endpoints.get_account_notifications
    parameters:
      - in: path
        name: account-name
        required: true
        schema:
          type: string
        description: Account whose notifications are listed
      - in: query
        name: type
        required: false
        schema:
          type: string
          default: NULL
        description: |
          Comma-separated notification types to return, e.g. `reply,mention`; all types when absent
      - in: query
        name: community
        required: false
        schema:
          type: string
          default: NULL
        description: Only notifications about this community
      - in: query
        name: min-score
        required: false
        schema:
          type: integer
          default: NULL
        description: Minimum notification score, 0 to 100, 25 by default
      - in: query
        name: limit
        required: false
        schema:
          type: integer
          default: NULL
        description: Maximum number of notifications to return, at most 100 (the default)
      - in: query
        name: last-id
        required: false
        schema:
          type: integer
          x-sql-datatype: BIGINT
          default: NULL
        description: Id of the last notification of the previous page
    responses:
      '200':
        description: |
          The account''s notifications

          * Returns `SETOF JSONB`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hivemind_endpoints.array_of_notification'
              x-sql-datatype: SETOF JSONB
      '400':
        description: Unknown account or community, unknown notification type, or an invalid parameter
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hivemind_endpoints.get_account_notifications;
CREATE OR REPLACE FUNCTION hivemind_endpoints.get_account_notifications(
    "account-name" TEXT,
    "type" TEXT = NULL,
    "community" TEXT = NULL,
    "min-score" INT = NULL,
    "limit" INT = NULL,
    "last-id" BIGINT = NULL
)
RETURNS SETOF JSONB 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN QUERY SELECT * FROM hivemind_postgrest_utilities.rest_json_rpc_rows('bridge', 'account_notifications',
    jsonb_build_object(
      'account', "account-name",
      'type', to_jsonb(NULLIF(string_to_array("type", ','), '{}')),
      'community', "community",
      'min_score', "min-score",
      'limit', hivemind_postgrest_utilities.rest_page_limit("limit", 100),
      'last_id', "last-id"));
END
$$;
