/** openapi:paths
/posts:
  get:
    tags:
      - blog_api
    summary: Get ranked posts
    description: |
      Returns posts ranked by `sort`, optionally within a tag or community, the same list as
      `bridge.get_ranked_posts`.

      To fetch the next page pass the `author` and `permlink` of the last post of the previous page
      as `start-author` and `start-permlink`.

      SQL example
      * `SELECT hivemind_endpoints.get_ranked_posts(''trending'', ''photography'', 20);`

      REST call example
      * `GET ''https://%1$s/hivemind-api/posts?sort=trending&tag=photography&limit=20''`
    operationId: hivemind_endpoints.get_ranked_posts
    parameters:
      - in: query
        name: sort
        required: true
        schema:
          type: string
          default: NULL
        description: |
          Ranking: `trending`, `hot`, `created`, `payout`, `payout_comments` or `muted`
      - in: query
        name: tag
        required: false
        schema:
          type: string
          default: NULL
        description: Tag or community name (`hive-NNNNNN`); `my` lists the observer''s communities
      - in: query
        name: limit
        required: false
        schema:
          type: integer
          default: NULL
        description: Maximum number of posts to return, at most the posts-per-call limit (20 unless configured), which is also the default
      - in: query
        name: start-author
        required: false
        schema:
          type: string
          default: NULL
        description: Author of the last post of the previous page
      - in: query
        name: start-permlink
        required: false
        schema:
          type: string
          default: NULL
        description: Permlink of the last post of the previous page
      - in: query
        name: observer
        required: false
        schema:
          type: string
          default: NULL
        description: |
          Account whose mutes and blacklists are applied. The response without an observer
          is the one meant for caching.
    responses:
      '200':
        description: |
          Ranked posts

          * Returns `SETOF JSONB`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hivemind_endpoints.array_of_bridge_post'
              x-sql-datatype: SETOF JSONB
      '400':
        description: Unsupported sort, unknown tag or start post, or an invalid parameter
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hivemind_endpoints.get_ranked_posts;
CREATE OR REPLACE FUNCTION hivemind_endpoints.get_ranked_posts(
    "sort" TEXT = NULL,
    "tag" TEXT = NULL,
    "limit" INT = NULL,
    "start-author" TEXT = NULL,
    "start-permlink" TEXT = NULL,
    "observer" TEXT = NULL
)
RETURNS SETOF JSONB 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN QUERY SELECT * FROM hivemind_postgrest_utilities.rest_json_rpc_rows('bridge', 'get_ranked_posts',
    jsonb_build_object(
      'sort', "sort",
      'tag', "tag",
      'limit', hivemind_postgrest_utilities.rest_page_limit("limit", hivemind_postgrest_utilities.get_max_posts_per_call_limit()),
      'start_author', "start-author",
      'start_permlink', "start-permlink",
      'observer', "observer"));
END
$$;
