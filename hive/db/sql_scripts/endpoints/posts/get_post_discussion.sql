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
      * `GET ''https://%1$s/hivemind-api/posts/alice/my-awesome-post/discussion?votes=none''`
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
      - in: query
        name: votes
        required: false
        schema:
          type: string
          enum: [full, summary, none]
          default: full
        description: |
          Votes included in each post of the discussion, with the same values as on `/posts`:

          * `full`, the default: `active_votes`, as the JSON-RPC method returns it.
          * `summary`: no `active_votes`; `top_votes` lists the 10 votes with the largest
            absolute `rshares` (ties by voter account id) as `voter`, `rshares` and `percent`,
            leaving out voters the observer muted.
          * `none`: no `active_votes` and no `top_votes`.

          With `summary` and `none` each post also has `observer_vote`, the observer''s vote
          (`rshares` and `percent`) or `null`, as in `bridge.get_discussion_v2`. The vote count
          (`stats.total_votes`) and `net_rshares` are in every form. With `none` the posts''
          votes are not read at all, so a large thread is both much smaller and faster to build.
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
    "observer" TEXT = NULL,
    "votes" TEXT = 'full'
)
RETURNS JSONB 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN hivemind_postgrest_utilities.rest_post_call('bridge', 'get_discussion',
    jsonb_build_object('author', "author", 'permlink', "permlink", 'observer', "observer"),
    "votes");
END
$$;
