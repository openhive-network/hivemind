/** openapi:paths
/accounts/{account-name}/votes:
  get:
    tags:
      - blog_api
    summary: Get votes cast by an account, newest first
    description: |
      Returns the votes cast by the account ordered by the time each vote was last updated, newest first
      (ties are broken by the vote''s internal id, newest first).

      To fetch the next page pass the `last_update`, `author` and `permlink` of the last vote of the
      previous page as `before`, `start-author` and `start-permlink`; consecutive pages then neither
      repeat nor skip a vote. `before` alone returns the votes last updated strictly before that time.

      SQL example
      * `SELECT * FROM hivemind_endpoints.get_account_votes(''blocktrades'', 20);`

      REST call example
      * `GET ''https://%1$s/hivemind-api/accounts/blocktrades/votes?page-size=20''`
      * `GET ''https://%1$s/hivemind-api/accounts/blocktrades/votes?page-size=20&before=2016-09-15T19:47:21&start-author=alice&start-permlink=my-awesome-post''`
    operationId: hivemind_endpoints.get_account_votes
    parameters:
      - in: path
        name: account-name
        required: true
        schema:
          type: string
        description: Account whose votes are listed
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
        name: before
        required: false
        schema:
          type: string
          format: date-time
          default: NULL
        description: Return votes last updated before this time (`last_update` of the last vote of the previous page)
      - in: query
        name: start-author
        required: false
        schema:
          type: string
          default: NULL
        description: Author of the post of the last vote of the previous page
      - in: query
        name: start-permlink
        required: false
        schema:
          type: string
          default: NULL
        description: Permlink of the post of the last vote of the previous page
    responses:
      '200':
        description: |
          Votes cast by the account, newest first

          * Returns `SETOF hivemind_endpoints.account_vote`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hivemind_endpoints.array_of_account_vote'
            example: [
              {
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
        description: Unknown account, unknown start post, or the account has not voted on the start post
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hivemind_endpoints.get_account_votes;
CREATE OR REPLACE FUNCTION hivemind_endpoints.get_account_votes(
    "account-name" TEXT,
    "page-size" INT = 20,
    "before" TIMESTAMP = NULL,
    "start-author" TEXT = NULL,
    "start-permlink" TEXT = NULL
)
RETURNS SETOF hivemind_endpoints.account_vote 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
  _voter_id INT;
  _limit INT;
  _start_post_id INT;
  _before_last_update TIMESTAMP := COALESCE("before", 'infinity'::TIMESTAMP);
  -- 0 makes `before` alone a strict bound: no vote id is below it
  _before_vote_id BIGINT := 0;
  _start_vote_last_update TIMESTAMP;
BEGIN
  _voter_id = hivemind_postgrest_utilities.find_account_id(
    hivemind_postgrest_utilities.valid_account("account-name", False),
    False);
  IF _voter_id = 0 THEN
    RAISE EXCEPTION 'Account ''%'' does not exist', "account-name";
  END IF;

  _limit = hivemind_postgrest_utilities.rest_page_size("page-size", 20, 1000);

  IF (COALESCE("start-author", '') = '') <> (COALESCE("start-permlink", '') = '') THEN
    RAISE EXCEPTION 'start-author and start-permlink must be given together';
  END IF;

  IF COALESCE("start-author", '') <> '' THEN
    _start_post_id = hivemind_postgrest_utilities.find_comment_id(
      hivemind_postgrest_utilities.valid_account("start-author", False),
      hivemind_postgrest_utilities.valid_permlink("start-permlink", False),
      False);
    IF _start_post_id = 0 THEN
      RAISE EXCEPTION 'Post @%/% does not exist', "start-author", "start-permlink";
    END IF;

    SELECT hv.id, hv.last_update INTO _before_vote_id, _start_vote_last_update
    FROM hivemind_app.hive_votes hv
    WHERE hv.post_id = _start_post_id AND hv.voter_id = _voter_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION '% has not voted on @%/%', "account-name", "start-author", "start-permlink";
    END IF;

    _before_last_update = COALESCE("before", _start_vote_last_update);
  END IF;

  RETURN QUERY
    SELECT *
    FROM jsonb_populate_recordset(
      NULL::hivemind_endpoints.account_vote,
      hivemind_postgrest_utilities.list_votes(
        0, 0, _limit,
        'list_by_voter_last_update_before'::hivemind_postgrest_utilities.list_votes_case,
        'database_api'::hivemind_postgrest_utilities.vote_presentation,
        _voter_id, NULL, NULL, _before_last_update, _before_vote_id));
END
$$;
