DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_active_votes;
CREATE FUNCTION hivemind_endpoints.condenser_api_get_active_votes(IN _params JSONB)
RETURNS JSON
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _observer TEXT;
  _observer_id INTEGER;
  _post_id INT;
BEGIN
  _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"author": "string","permlink": "string", "observer": "string"}', 2, NULL);

  _post_id =
    hivemind_postgrest_utilities.find_comment_id(
      hivemind_postgrest_utilities.valid_account(
        hivemind_postgrest_utilities.parse_argument_from_json(_params, 'author', True),
        False),
      hivemind_postgrest_utilities.valid_permlink(
        hivemind_postgrest_utilities.parse_argument_from_json(_params, 'permlink', True),
        False),
      True);

  _observer = hivemind_postgrest_utilities.parse_argument_from_json(_params, 'observer', False);
  _observer_id = hivemind_postgrest_utilities.find_account_id(
    hivemind_postgrest_utilities.valid_account(_observer, True),
    False);

  RETURN hivemind_postgrest_utilities.list_votes(_observer_id, _post_id, 1000, 'get_votes_for_posts'::hivemind_postgrest_utilities.list_votes_case, 'active_votes'::hivemind_postgrest_utilities.vote_presentation);
END;
$$
;
