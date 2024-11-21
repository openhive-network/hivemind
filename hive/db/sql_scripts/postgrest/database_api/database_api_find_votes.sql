DROP FUNCTION IF EXISTS hivemind_endpoints.database_api_find_votes;
CREATE FUNCTION hivemind_endpoints.database_api_find_votes(IN _json_is_object BOOLEAN, IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _post_id INT;
BEGIN
  PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"author","permlink"}', '{"string","string"}');

  _post_id =
    hivemind_postgrest_utilities.find_comment_id(
      hivemind_postgrest_utilities.valid_account(
        hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'author', 0, True),
        False),
      hivemind_postgrest_utilities.valid_permlink(
        hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'permlink', 1, True),
        False),
      True);

  RETURN jsonb_build_object(
      'votes',
      hivemind_postgrest_utilities.list_votes(_post_id, 1000, 'get_votes_for_posts'::hivemind_postgrest_utilities.list_votes_case, 'database_api'::hivemind_postgrest_utilities.vote_presentation)
    );
END;
$$
;