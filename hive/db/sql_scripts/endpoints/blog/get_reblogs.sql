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
      * `SELECT * FROM hivemind_endpoints.get_reblogs('trending', '', 'alice', 20);`

      REST call example
      * `GET 'https://%1$s/hivemind-api/blog/reblogs?sort=trending&observer=alice&limit=20'`
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
          Filter by tag, community name, 'my' for observer's subscribed communities, or empty/'all' for all posts
      - in: query
        name: observer
        required: true
        schema:
          type: string
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
              type: array
              items:
                $ref: '#/components/schemas/hivemind_endpoints.reblog_status'
            example: [
              {
                "post_id": 141560746,
                "author": "hiveio",
                "permlink": "hive-5-celebrating-our-5th-anniversary-as-hive",
                "reblogged": true
              },
              {
                "post_id": 141559832,
                "author": "alice",
                "permlink": "my-awesome-post",
                "reblogged": false
              }
            ]
      '400':
        description: Invalid parameters (missing observer or invalid sort)
 */

-- Define the return type for reblog status
DROP TYPE IF EXISTS hivemind_endpoints.reblog_status CASCADE;
CREATE TYPE hivemind_endpoints.reblog_status AS (
    post_id INT,
    author TEXT,
    permlink TEXT,
    reblogged BOOLEAN
);

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
  _limit INT;
  _tag TEXT;
  _post_id INT;
  _observer_id INT;
  _sort_type hivemind_postgrest_utilities.ranked_post_sort_type;
BEGIN
  -- Validate observer is provided
  IF "observer" IS NULL OR "observer" = '' THEN
    RAISE EXCEPTION 'observer is required for this endpoint';
  END IF;

  -- Validate and set limit
  _limit = LEAST(COALESCE("limit", 20), hivemind_postgrest_utilities.get_max_posts_per_call_limit());
  IF _limit < 1 THEN
    _limit = 1;
  END IF;

  -- Find start post for pagination
  _post_id = hivemind_postgrest_utilities.find_comment_id(
    hivemind_postgrest_utilities.valid_account("start-author", True),
    hivemind_postgrest_utilities.valid_permlink("start-permlink", True),
    True);

  -- Validate tag
  _tag = hivemind_postgrest_utilities.valid_tag(
    hivemind_postgrest_utilities.valid_tag("tag", True),
    True);

  -- Find observer account id
  _observer_id = hivemind_postgrest_utilities.find_account_id(
    hivemind_postgrest_utilities.valid_account("observer", False),
    True);

  IF _observer_id = 0 THEN
    RAISE EXCEPTION 'observer account not found';
  END IF;

  -- Parse sort type
  CASE "sort"
    WHEN 'trending' THEN _sort_type = 'trending';
    WHEN 'hot' THEN _sort_type = 'hot';
    WHEN 'created' THEN _sort_type = 'created';
    WHEN 'payout' THEN _sort_type = 'payout';
    WHEN 'payout_comments' THEN _sort_type = 'payout_comments';
    WHEN 'muted' THEN _sort_type = 'muted';
    ELSE RAISE EXCEPTION 'Unsupported sort, valid sorts: trending, hot, created, payout, payout_comments, muted';
  END CASE;

  -- Return reblog status for posts matching the criteria
  IF _tag IS NULL OR _tag = '' OR _tag = 'all' THEN
    RETURN QUERY SELECT * FROM hivemind_postgrest_utilities.get_reblogged_posts_for_all(_post_id, _observer_id, _limit, _sort_type);
  ELSIF _tag = 'my' THEN
    RETURN QUERY SELECT * FROM hivemind_postgrest_utilities.get_reblogged_posts_for_observer_communities(_post_id, _observer_id, _limit, _sort_type);
  ELSIF hivemind_postgrest_utilities.check_community(_tag) THEN
    RETURN QUERY SELECT * FROM hivemind_postgrest_utilities.get_reblogged_posts_for_community(_post_id, _observer_id, _limit, _tag, _sort_type);
  ELSE
    RETURN QUERY SELECT * FROM hivemind_postgrest_utilities.get_reblogged_posts_for_tag(_post_id, _observer_id, _limit, _tag, _sort_type);
  END IF;
END
$$;
