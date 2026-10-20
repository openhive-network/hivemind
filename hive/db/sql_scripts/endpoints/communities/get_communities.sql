/** openapi:paths
/communities:
  get:
    tags:
      - blog_api
    summary: List communities
    description: |
      Returns communities ordered by `sort`, optionally only those matching `query`, the same list as
      `bridge.list_communities`.

      To fetch the next page pass the `name` of the last community of the previous page as `last`.

      SQL example
      * `SELECT hivemind_endpoints.get_communities(''rank'', NULL, 20);`

      REST call example
      * `GET ''https://%1$s/hivemind-api/communities?sort=rank&limit=20''`
    operationId: hivemind_endpoints.get_communities
    parameters:
      - in: query
        name: sort
        required: false
        schema:
          type: string
          default: NULL
        description: '`rank` (the default), `new` or `subs`'
      - in: query
        name: query
        required: false
        schema:
          type: string
          default: NULL
        description: Words the community''s title or about text must contain
      - in: query
        name: limit
        required: false
        schema:
          type: integer
          default: NULL
        description: Maximum number of communities to return, at most 100 (the default)
      - in: query
        name: last
        required: false
        schema:
          type: string
          default: NULL
        description: Name of the last community of the previous page
      - in: query
        name: observer
        required: false
        schema:
          type: string
          default: NULL
        description: |
          Account whose subscription and role is reported in each community''s `context`. The response
          without an observer is the one meant for caching.
    responses:
      '200':
        description: |
          Communities

          * Returns `SETOF JSONB`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hivemind_endpoints.array_of_bridge_community'
              x-sql-datatype: SETOF JSONB
      '400':
        description: Unsupported sort, unknown last community, or an invalid parameter
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hivemind_endpoints.get_communities;
CREATE OR REPLACE FUNCTION hivemind_endpoints.get_communities(
    "sort" TEXT = NULL,
    "query" TEXT = NULL,
    "limit" INT = NULL,
    "last" TEXT = NULL,
    "observer" TEXT = NULL
)
RETURNS SETOF JSONB 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN QUERY SELECT * FROM hivemind_postgrest_utilities.rest_json_rpc_rows('bridge', 'list_communities',
    jsonb_build_object('sort', "sort", 'query', "query", 'limit', hivemind_postgrest_utilities.rest_page_limit("limit", 100), 'last', "last", 'observer', "observer"));
END
$$;
