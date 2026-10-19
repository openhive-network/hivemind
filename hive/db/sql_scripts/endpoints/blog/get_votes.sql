/** openapi:paths
/blog/votes:
  get:
    tags:
      - blog_api
    summary: Get vote status for ranked posts
    description: |
      Returns the observer''s vote on each post matching the same criteria as bridge.get_ranked_posts.
      This is a lightweight endpoint that only returns post identifiers, whether the observer has voted on each post
      and the percent of that vote, so a front end can cache the anonymous feed and fetch this overlay separately.
      A vote the observer later removed is still reported as `voted` with `vote_percent` 0, as it still appears
      in the post''s active votes.

      SQL example
      * `SELECT * FROM hivemind_endpoints.get_votes(''trending'', '''', ''alice'', 20);`

      REST call example
      * `GET ''https://%1$s/hivemind-api/blog/votes?sort=trending&observer=alice&limit=20''`
    operationId: hivemind_endpoints.get_votes
    parameters:
      - in: query
        name: sort
        required: true
        schema:
          type: string
          enum: [trending, hot, created, payout, payout_comments, muted]
        description: Sorting method for posts
      - in: query
        name: tag
        required: false
        schema:
          type: string
          default: ''
        description: |
          Filter by tag, community name, ''my'' for observer''s subscribed communities, or empty/''all'' for all posts
      - in: query
        name: observer
        required: false
        schema:
          type: string
          default: NULL
        description: Account name to check vote status for (required)
      - in: query
        name: limit
        required: false
        schema:
          type: integer
          default: 20
          minimum: 1
        description: Maximum number of posts to return
      - in: query
        name: start-author
        required: false
        schema:
          type: string
          default: NULL
        description: Author of post to start pagination from
      - in: query
        name: start-permlink
        required: false
        schema:
          type: string
          default: NULL
        description: Permlink of post to start pagination from
    responses:
      '200':
        description: |
          Array of posts with the observer''s vote status

          * Returns `SETOF hivemind_endpoints.vote_status`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hivemind_endpoints.array_of_vote_status'
            example: [
              {
                "author": "hiveio",
                "permlink": "hive-5-celebrating-our-5th-anniversary-as-hive",
                "voted": true,
                "vote_percent": 10000
              },
              {
                "author": "alice",
                "permlink": "my-awesome-post",
                "voted": false,
                "vote_percent": 0
              }
            ]
      '400':
        description: Invalid parameters (missing observer or invalid sort)
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hivemind_endpoints.get_votes;
CREATE OR REPLACE FUNCTION hivemind_endpoints.get_votes(
    "sort" TEXT,
    "tag" TEXT = '',
    "observer" TEXT = NULL,
    "limit" INT = 20,
    "start-author" TEXT = NULL,
    "start-permlink" TEXT = NULL
)
RETURNS SETOF hivemind_endpoints.vote_status 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
  _request hivemind_postgrest_utilities.ranked_posts_overlay_request;
BEGIN
  _request = hivemind_postgrest_utilities.valid_ranked_posts_overlay_request(
    "sort", "tag", "observer", "limit", "start-author", "start-permlink");

  RETURN QUERY
    SELECT
      p.author,
      p.permlink,
      (hv.id IS NOT NULL),
      COALESCE(hv.vote_percent, 0)
    FROM hivemind_postgrest_utilities.get_ranked_posts_overlay(_request) WITH ORDINALITY AS p(post_id, author, permlink, ord)
    LEFT JOIN hivemind_app.hive_votes hv ON hv.post_id = p.post_id AND hv.voter_id = _request.observer_id
    ORDER BY p.ord;
END
$$;
