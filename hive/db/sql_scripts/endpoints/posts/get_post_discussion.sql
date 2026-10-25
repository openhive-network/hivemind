/** openapi:paths
/posts/{author}/{permlink}/discussion:
  get:
    tags:
      - blog_api
    summary: Get a post''s whole discussion
    description: |
      Returns the whole thread of the post in one response, the same object as `bridge.get_discussion`:
      every post of the thread, the post itself included, keyed by `author/permlink`. Each post is the
      same object as in `bridge.get_discussion`; its `replies` field names its direct replies, in the
      order they were made, so the tree is rebuilt from the post''s own entry down.

      The response is not paged by the posts-per-call limit. Like `bridge.get_discussion`, it holds
      at most the first 4000 posts of a thread, in the order they were made; the `replies` of a cut
      thread name only the posts the response holds.

      SQL example
      * `SELECT hivemind_endpoints.get_post_discussion(''alice'', ''my-awesome-post'');`

      REST call example
      * `GET ''https://%1$s/hivemind-api/posts/alice/my-awesome-post/discussion''`
    operationId: hivemind_endpoints.get_post_discussion
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
          The discussion

          * Returns `JSONB`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hivemind_endpoints.discussion'
              x-sql-datatype: JSONB
      '400':
        description: Unknown post, or an invalid parameter
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hivemind_endpoints.get_post_discussion;
CREATE OR REPLACE FUNCTION hivemind_endpoints.get_post_discussion(
    "author" TEXT,
    "permlink" TEXT,
    "observer" TEXT = NULL
)
RETURNS JSONB 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN hivemind_postgrest_utilities.rest_json_rpc_call('bridge', 'get_discussion',
    jsonb_build_object('author', "author", 'permlink', "permlink", 'observer', "observer"));
END
$$;
