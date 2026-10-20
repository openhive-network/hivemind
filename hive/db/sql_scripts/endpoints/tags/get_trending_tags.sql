/** openapi:paths
/tags/trending:
  get:
    tags:
      - blog_api
    summary: Get trending topics
    description: |
      Returns the trending communities and tags, the same list as `bridge.get_trending_topics`.
      Each row is `[name, title]`.

      SQL example
      * `SELECT hivemind_endpoints.get_trending_tags(10);`

      REST call example
      * `GET ''https://%1$s/hivemind-api/tags/trending?page-size=10''`
    operationId: hivemind_endpoints.get_trending_tags
    parameters:
      - in: query
        name: page-size
        required: false
        schema:
          type: integer
          default: NULL
        description: Maximum number of topics to return, at most 25; the default is 10
      - in: query
        name: observer
        required: false
        schema:
          type: string
          default: NULL
        description: |
          Accepted for parity with `bridge.get_trending_topics`. The response without an observer
          is the one meant for caching.
    responses:
      '200':
        description: |
          Trending topics

          * Returns `SETOF JSONB`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hivemind_endpoints.array_of_string_tuple'
              x-sql-datatype: SETOF JSONB
      '400':
        description: An invalid parameter
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hivemind_endpoints.get_trending_tags;
CREATE OR REPLACE FUNCTION hivemind_endpoints.get_trending_tags(
    "page-size" INT = NULL,
    "observer" TEXT = NULL
)
RETURNS SETOF JSONB 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN QUERY SELECT * FROM hivemind_postgrest_utilities.rest_json_rpc_rows('bridge', 'get_trending_topics',
    jsonb_build_object('limit', "page-size", 'observer', "observer"));
END
$$;
