/** openapi:paths
/search/posts:
  get:
    tags:
      - blog_api
    summary: Search posts
    description: |
      Returns the posts and comments matching the full-text query `q`, the same list as
      `search-api.find_text`. Needs the `pg_search` extension.

      To fetch the next page pass the `author` and `permlink` of the last post of the previous page
      as `start-author` and `start-permlink`.

      SQL example
      * `SELECT hivemind_endpoints.search_posts(''beekeeping'', ''relevance'');`

      REST call example
      * `GET ''https://%1$s/hivemind-api/search/posts?q=beekeeping&sort=relevance&page-size=20''`
    operationId: hivemind_endpoints.search_posts
    parameters:
      - in: query
        name: q
        required: true
        schema:
          type: string
          default: NULL
        description: |
          Search query; supports quoted phrases, `+`/`-` terms and field prefixes as `search-api.find_text` does
      - in: query
        name: sort
        required: true
        schema:
          type: string
          default: NULL
        description: '`relevance` or `created`'
      - in: query
        name: author
        required: false
        schema:
          type: string
          default: NULL
        description: Only posts by this account
      - in: query
        name: page-size
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
          Account whose mutes are applied. The response without an observer
          is the one meant for caching.
    responses:
      '200':
        description: |
          Matching posts

          * Returns `SETOF JSONB`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hivemind_endpoints.array_of_bridge_post'
              x-sql-datatype: SETOF JSONB
      '400':
        description: Unsupported sort, unknown account or start post, an invalid parameter, or no full-text search
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hivemind_endpoints.search_posts;
CREATE OR REPLACE FUNCTION hivemind_endpoints.search_posts(
    "q" TEXT = NULL,
    "sort" TEXT = NULL,
    "author" TEXT = NULL,
    "page-size" INT = NULL,
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
  RETURN QUERY SELECT * FROM hivemind_postgrest_utilities.rest_json_rpc_rows('search-api', 'find_text',
    jsonb_build_object(
      'pattern', "q",
      'sort', "sort",
      'author', "author",
      'limit', "page-size",
      'start_author', "start-author",
      'start_permlink', "start-permlink",
      'observer', "observer"));
END
$$;
