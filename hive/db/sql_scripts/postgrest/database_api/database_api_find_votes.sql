DROP FUNCTION IF EXISTS hivemind_endpoints.database_api_find_votes;
CREATE FUNCTION hivemind_endpoints.database_api_find_votes(IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _post_id INT;
BEGIN
  _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"author": "string", "permlink": "string"}', 2, NULL);

  _post_id =
    hivemind_postgrest_utilities.find_comment_id(
      hivemind_postgrest_utilities.valid_account(
        hivemind_postgrest_utilities.parse_argument_from_json(_params, 'author', True),
        False),
      hivemind_postgrest_utilities.valid_permlink(
        hivemind_postgrest_utilities.parse_argument_from_json(_params, 'permlink', True),
        False),
      True);

  RETURN jsonb_build_object(
      'votes',
      hivemind_postgrest_utilities.list_votes(_post_id, 1000, 'get_votes_for_posts'::hivemind_postgrest_utilities.list_votes_case, 'database_api'::hivemind_postgrest_utilities.vote_presentation)
    );
END;
$$
;