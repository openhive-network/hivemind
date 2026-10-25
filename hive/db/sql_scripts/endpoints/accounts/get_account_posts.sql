/** openapi:paths
/accounts/{account-name}/posts:
  get:
    tags:
      - blog_api
    summary: Get an account''s posts
    description: |
      Returns the account''s posts of the kind given by `sort`, the same list as `bridge.get_account_posts`.

      To fetch the next page pass the `author` and `permlink` of the last post of the previous page
      as `start-author` and `start-permlink`.

      SQL example
      * `SELECT hivemind_endpoints.get_account_posts(''alice'', ''blog'');`

      REST call example
      * `GET ''https://%1$s/hivemind-api/accounts/alice/posts?sort=blog&page-size=20''`
    operationId: hivemind_endpoints.get_account_posts
    parameters:
      - in: path
        name: account-name
        required: true
        schema:
          type: string
        description: Account whose posts are listed
      - in: query
        name: sort
        required: true
        schema:
          type: string
          default: NULL
        description: |
          Kind of posts: `blog`, `feed`, `posts`, `comments`, `replies` or `payout`
      - in: query
        name: community
        required: false
        schema:
          type: string
          default: NULL
        description: Only posts in this community; allowed with `sort` `posts` and `comments`
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
          Account whose mutes and blacklists are applied. The response without an observer
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
          The account''s posts

          * Returns `SETOF JSONB`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hivemind_endpoints.array_of_bridge_post'
              x-sql-datatype: SETOF JSONB
      '400':
        description: Unknown account, community or start post, unsupported sort, or an invalid parameter
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hivemind_endpoints.get_account_posts;
CREATE OR REPLACE FUNCTION hivemind_endpoints.get_account_posts(
    "account-name" TEXT,
    "sort" TEXT = NULL,
    "community" TEXT = NULL,
    "page-size" INT = NULL,
    "start-author" TEXT = NULL,
    "start-permlink" TEXT = NULL,
    "observer" TEXT = NULL,
    "truncate-body" INT = NULL
)
RETURNS SETOF JSONB 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN QUERY SELECT * FROM hivemind_postgrest_utilities.rest_json_rpc_rows('bridge', 'get_account_posts',
    jsonb_build_object(
      'account', "account-name",
      'sort', "sort",
      'community', "community",
      'limit', "page-size",
      'start_author', "start-author",
      'start_permlink', "start-permlink",
      'observer', "observer",
      'truncate_body', "truncate-body"));
END
$$;
