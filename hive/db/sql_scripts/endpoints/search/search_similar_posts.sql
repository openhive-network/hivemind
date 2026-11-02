/** openapi:paths
/posts/{author}/{permlink}/similar:
  get:
    tags:
      - blog_api
    summary: Get posts similar to a post
    description: |
      Returns the top-level posts most similar in wording to the given post, the same list as
      `search-api.find_similar`, most similar first and without the post itself. Similarity is
      the BM25 score of a more-like-this query built from the post''s title and body, so it needs
      the `pg_search` extension. A comment, or a post too short to have distinctive terms,
      has no similar posts.

      SQL example
      * `SELECT hivemind_endpoints.search_similar_posts(''alice'', ''my-awesome-post'');`

      REST call example
      * `GET ''https://%1$s/hivemind-api/posts/alice/my-awesome-post/similar?page-size=10''`
    operationId: hivemind_endpoints.search_similar_posts
    parameters:
      - in: path
        name: author
        required: true
        schema:
          type: string
        description: Author of the post
      - in: path
        name: permlink
        required: true
        schema:
          type: string
        description: Permlink of the post
      - in: query
        name: page-size
        required: false
        schema:
          type: integer
          default: NULL
        description: Maximum number of posts to return, at most the posts-per-call limit (20 unless configured), which is also the default
      - in: query
        name: observer
        required: false
        schema:
          type: string
          default: NULL
        description: |
          Account whose mutes are applied. The response without an observer
          is the one meant for caching.
      - in: query
        name: truncate-body
        required: false
        schema:
          type: integer
          default: NULL
        description: |
          Cut each post''s `body` to at most this many characters, as the `truncate_body` argument
          of the JSON-RPC method does, for clients that show post cards rather than whole posts.
          `0`, the default, returns the whole body.
    responses:
      '200':
        description: |
          Similar posts

          * Returns `SETOF JSONB`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hivemind_endpoints.array_of_bridge_post'
              x-sql-datatype: SETOF JSONB
      '400':
        description: Unknown post, an invalid parameter, or no full-text search
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hivemind_endpoints.search_similar_posts;
CREATE OR REPLACE FUNCTION hivemind_endpoints.search_similar_posts(
    "author" TEXT,
    "permlink" TEXT,
    "page-size" INT = NULL,
    "observer" TEXT = NULL,
    "truncate-body" INT = NULL
)
RETURNS SETOF JSONB 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN QUERY SELECT * FROM hivemind_postgrest_utilities.rest_json_rpc_rows('search-api', 'find_similar',
    jsonb_build_object(
      'author', "author",
      'permlink', "permlink",
      'limit', "page-size",
      'observer', "observer",
      'truncate_body', "truncate-body"));
END
$$;
