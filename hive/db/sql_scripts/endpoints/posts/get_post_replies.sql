/** openapi:paths
/posts/{author}/{permlink}/replies:
  get:
    tags:
      - blog_api
    summary: Get the replies to a post
    description: |
      Returns the posts of `bridge.get_discussion` for the post other than the post itself, as a list
      ordered by creation time (ties broken by `author/permlink`), so new replies are added at the end.
      Each reply is the same object as in `bridge.get_discussion`; its `replies` field names its own
      direct replies. Like `bridge.get_discussion`, only the first 4000 posts of a thread are included.

      To fetch the next page pass the `author` and `permlink` of the last reply of the previous page
      as `start-author` and `start-permlink`.

      SQL example
      * `SELECT hivemind_endpoints.get_post_replies(''alice'', ''my-awesome-post'', 20);`

      REST call example
      * `GET ''https://%1$s/hivemind-api/posts/alice/my-awesome-post/replies?limit=20''`
    operationId: hivemind_endpoints.get_post_replies
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
        name: limit
        required: false
        schema:
          type: integer
          default: NULL
        description: Maximum number of replies to return, at most the posts-per-call limit (20 unless configured), which is also the default
      - in: query
        name: start-author
        required: false
        schema:
          type: string
          default: NULL
        description: Author of the last reply of the previous page
      - in: query
        name: start-permlink
        required: false
        schema:
          type: string
          default: NULL
        description: Permlink of the last reply of the previous page
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
          Replies to the post

          * Returns `SETOF JSONB`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hivemind_endpoints.array_of_bridge_post'
              x-sql-datatype: SETOF JSONB
      '400':
        description: Unknown post, a start reply that is not in the discussion, or an invalid parameter
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hivemind_endpoints.get_post_replies;
CREATE OR REPLACE FUNCTION hivemind_endpoints.get_post_replies(
    "author" TEXT,
    "permlink" TEXT,
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
DECLARE
  _discussion JSONB;
  _root_key TEXT := "author" || '/' || "permlink";
  _start_key TEXT;
  _start_created TEXT;
BEGIN
  _discussion = hivemind_postgrest_utilities.rest_json_rpc_call('bridge', 'get_discussion',
    jsonb_build_object('author', "author", 'permlink', "permlink", 'observer', "observer"));

  IF COALESCE("start-author", '') <> '' OR COALESCE("start-permlink", '') <> '' THEN
    _start_key = COALESCE("start-author", '') || '/' || COALESCE("start-permlink", '');
    _start_created = _discussion -> _start_key ->> 'created';
    IF _start_key = _root_key OR _start_created IS NULL THEN
      RAISE EXCEPTION 'Post @% is not a reply in the discussion of @%', _start_key, _root_key;
    END IF;
  END IF;

  -- `created` is an ISO 8601 timestamp, so it sorts as text
  RETURN QUERY
    SELECT reply.value
    FROM jsonb_each(_discussion) reply
    WHERE reply.key <> _root_key
      AND (_start_key IS NULL OR ((reply.value ->> 'created') COLLATE "C", reply.key COLLATE "C") > (_start_created COLLATE "C", _start_key COLLATE "C"))
    ORDER BY (reply.value ->> 'created') COLLATE "C", reply.key COLLATE "C"
    LIMIT hivemind_postgrest_utilities.rest_page_limit("limit", hivemind_postgrest_utilities.get_max_posts_per_call_limit());
END
$$;
