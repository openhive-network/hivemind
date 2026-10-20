/** openapi:paths
/communities/{name}/subscribers:
  get:
    tags:
      - blog_api
    summary: Get a community''s subscribers
    description: |
      Returns the community''s subscribers in account name order, the same list as `bridge.list_subscribers`.
      Each row is `[account, role, title, subscribed_at]`.

      To fetch the next page pass the account name of the last row of the previous page as `last`.

      SQL example
      * `SELECT hivemind_endpoints.get_community_subscribers(''hive-123456'');`

      REST call example
      * `GET ''https://%1$s/hivemind-api/communities/hive-123456/subscribers?page-size=100''`
    operationId: hivemind_endpoints.get_community_subscribers
    parameters:
      - in: path
        name: name
        required: true
        schema:
          type: string
        description: Name of the community (`hive-NNNNNN`)
      - in: query
        name: page-size
        required: false
        schema:
          type: integer
          default: NULL
        description: Maximum number of rows to return, at most 100 (the default)
      - in: query
        name: last
        required: false
        schema:
          type: string
          default: NULL
        description: Account of the last subscriber of the previous page
    responses:
      '200':
        description: |
          Get a community''s subscribers

          * Returns `SETOF JSONB`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hivemind_endpoints.array_of_string_tuple'
              x-sql-datatype: SETOF JSONB
      '400':
        description: Unknown community, a last account that is not subscribed, or an invalid parameter
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hivemind_endpoints.get_community_subscribers;
CREATE OR REPLACE FUNCTION hivemind_endpoints.get_community_subscribers(
    "name" TEXT,
    "page-size" INT = NULL,
    "last" TEXT = NULL
)
RETURNS SETOF JSONB 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN QUERY SELECT * FROM hivemind_postgrest_utilities.rest_json_rpc_rows('bridge', 'list_subscribers',
    jsonb_build_object('community', "name", 'limit', "page-size", 'last', "last"));
END
$$;
