/** openapi:paths
/posts/{author}/{permlink}/votes:
  get:
    tags:
      - blog_api
    summary: Get votes on a post
    description: |
      Returns the votes on one post or comment, in the same order as `database_api.list_votes` with
      `by_comment_voter` (by the voter''s account id, i.e. account creation order).

      To fetch the next page pass the `voter` of the last vote of the previous page as `start-voter`;
      the page starts after that voter.

      SQL example
      * `SELECT * FROM hivemind_endpoints.get_post_votes(''alice'', ''my-awesome-post'', 20);`

      REST call example
      * `GET ''https://%1$s/hivemind-api/posts/alice/my-awesome-post/votes?page-size=20''`
    operationId: hivemind_endpoints.get_post_votes
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
          default: 20
          minimum: 1
          maximum: 1000
        description: Maximum number of votes to return, at most 1000
      - in: query
        name: start-voter
        required: false
        schema:
          type: string
          default: NULL
        description: Voter of the last vote of the previous page; the page starts after this voter
    responses:
      '200':
        description: |
          Votes on the post

          * Returns `SETOF hivemind_endpoints.post_vote`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hivemind_endpoints.array_of_post_vote'
            example: [
              {
                "voter": "bob",
                "author": "alice",
                "permlink": "my-awesome-post",
                "weight": "1146353766",
                "rshares": "1879215360",
                "vote_percent": 10000,
                "last_update": "2016-09-15T19:47:21",
                "num_changes": 0
              }
            ]
      '400':
        description: Unknown post or unknown start voter
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hivemind_endpoints.get_post_votes;
CREATE OR REPLACE FUNCTION hivemind_endpoints.get_post_votes(
    "author" TEXT,
    "permlink" TEXT,
    "page-size" INT = 20,
    "start-voter" TEXT = NULL
)
RETURNS SETOF hivemind_endpoints.post_vote 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
  _post_id INT;
  _start_voter_id INT;
  _limit INT;
BEGIN
  _post_id = hivemind_postgrest_utilities.find_comment_id(
    hivemind_postgrest_utilities.valid_account("author", False),
    hivemind_postgrest_utilities.valid_permlink("permlink", False),
    False);
  IF _post_id = 0 THEN
    RAISE EXCEPTION 'Post @%/% does not exist', "author", "permlink";
  END IF;

  _start_voter_id = hivemind_postgrest_utilities.find_account_id(
    hivemind_postgrest_utilities.valid_account("start-voter", True),
    False);
  IF _start_voter_id = 0 AND COALESCE("start-voter", '') <> '' THEN
    RAISE EXCEPTION 'Account ''%'' does not exist', "start-voter";
  END IF;

  _limit = hivemind_postgrest_utilities.rest_page_size("page-size", 20, 1000);

  RETURN QUERY
    SELECT *
    FROM jsonb_populate_recordset(
      NULL::hivemind_endpoints.post_vote,
      hivemind_postgrest_utilities.list_votes(
        0, _post_id, _limit,
        'bridge_list_by_comment_voter_after'::hivemind_postgrest_utilities.list_votes_case,
        'database_api'::hivemind_postgrest_utilities.vote_presentation,
        _start_voter_id));
END
$$;
