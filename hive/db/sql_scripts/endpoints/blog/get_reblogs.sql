/** openapi:paths
/blog/reblogs:
  get:
    tags:
      - blog_api
    summary: Get reblog status for ranked posts
    description: |
      Returns reblog status for posts matching the same criteria as bridge.get_ranked_posts.
      This is a lightweight endpoint that only returns post identifiers and whether the observer has reblogged each post.

      SQL example
      * `SELECT * FROM hivemind_endpoints.get_reblogs(''trending'', '''', ''alice'', 20);`

      REST call example
      * `GET ''https://%1$s/hivemind-api/blog/reblogs?sort=trending&observer=alice&limit=20''`
    operationId: hivemind_endpoints.get_reblogs
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
        description: Account name to check reblog status for (required)
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
          Array of posts with reblog status

          * Returns `SETOF hivemind_endpoints.reblog_status`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hivemind_endpoints.array_of_reblog_status'
            example: [
              {
                "author": "hiveio",
                "permlink": "hive-5-celebrating-our-5th-anniversary-as-hive",
                "reblogged": true
              },
              {
                "author": "alice",
                "permlink": "my-awesome-post",
                "reblogged": false
              }
            ]
      '400':
        description: Invalid parameters (missing observer or invalid sort)
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hivemind_endpoints.get_reblogs;
CREATE OR REPLACE FUNCTION hivemind_endpoints.get_reblogs(
    "sort" TEXT,
    "tag" TEXT = '',
    "observer" TEXT = NULL,
    "limit" INT = 20,
    "start-author" TEXT = NULL,
    "start-permlink" TEXT = NULL
)
RETURNS SETOF hivemind_endpoints.reblog_status 
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
      (hr.post_id IS NOT NULL)
    FROM hivemind_postgrest_utilities.get_ranked_posts_overlay(_request) WITH ORDINALITY AS p(post_id, author, permlink, ord)
    LEFT JOIN hivemind_app.hive_reblogs hr ON hr.blogger_id = _request.observer_id AND hr.post_id = p.post_id
    ORDER BY p.ord;
END
$$;
