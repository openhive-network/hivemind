/** openapi:paths
/posts/{author}/{permlink}:
  get:
    tags:
      - blog_api
    summary: Get a post
    description: |
      Returns one post or comment, the same object as `bridge.get_post`.

      SQL example
      * `SELECT hivemind_endpoints.get_post(''alice'', ''my-awesome-post'');`

      REST call example
      * `GET ''https://%1$s/hivemind-api/posts/alice/my-awesome-post''`
      * `GET ''https://%1$s/hivemind-api/posts/alice/my-awesome-post?votes=summary''`
    operationId: hivemind_endpoints.get_post
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
          Account whose mutes and blacklists are applied. The response without an observer
          is the one meant for caching.
      - in: query
        name: votes
        required: false
        schema:
          type: string
          enum: [full, summary, none]
          default: full
        description: |
          Votes included in the post, with the same values as on `/posts`:

          * `full`, the default: `active_votes`, as the JSON-RPC method returns it.
          * `summary`: no `active_votes`; `top_votes` lists the 10 votes with the largest
            absolute `rshares` (ties by voter account id) as `voter`, `rshares` and `percent`,
            leaving out voters the observer muted.
          * `none`: no `active_votes` and no `top_votes`.

          With `summary` and `none` the post also has `observer_vote`, the observer''s vote
          (`rshares` and `percent`) or `null`, as in `bridge.get_post_v2`. The vote count
          (`stats.total_votes`) and `net_rshares` are in every form. `bridge.list_votes` pages
          through all of the post''s votes.
    responses:
      '200':
        description: |
          The post

          * Returns `JSONB`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hivemind_endpoints.bridge_post'
              x-sql-datatype: JSONB
      '400':
        description: Unknown or deleted post, or an invalid parameter
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hivemind_endpoints.get_post;
CREATE OR REPLACE FUNCTION hivemind_endpoints.get_post(
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
  RETURN hivemind_postgrest_utilities.rest_post_call('bridge', 'get_post',
    jsonb_build_object('author', "author", 'permlink', "permlink", 'observer', "observer"),
    "votes");
END
$$;
