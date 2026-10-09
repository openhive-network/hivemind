DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_list_votes;
CREATE FUNCTION hivemind_endpoints.bridge_api_list_votes(IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _post_id INT;
  _start_voter_id INT;
  _limit INT;
  _observer_id INT;
BEGIN
  _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"author": "string", "permlink": "string", "start": "string", "limit": "number", "observer": "string"}', 2, '{"permlink": "permlink must be string"}');

  _post_id = hivemind_postgrest_utilities.find_comment_id(
    hivemind_postgrest_utilities.valid_account(
      hivemind_postgrest_utilities.parse_argument_from_json(_params, 'author', True),
      False),
    hivemind_postgrest_utilities.valid_permlink(
      hivemind_postgrest_utilities.parse_argument_from_json(_params, 'permlink', True),
      False),
    True);

  -- 0 when no start is given: no account votes with id 0, so the first page starts at the lowest voter id
  _start_voter_id = hivemind_postgrest_utilities.find_account_id(
    hivemind_postgrest_utilities.valid_account(
      hivemind_postgrest_utilities.parse_argument_from_json(_params, 'start', False), True),
    True);

  _limit = hivemind_postgrest_utilities.valid_number(hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'limit', False), 100, 1, 1000, 'limit');

  _observer_id = hivemind_postgrest_utilities.find_account_id(
    hivemind_postgrest_utilities.valid_account(
      hivemind_postgrest_utilities.parse_argument_from_json(_params, 'observer', False), True),
    True);

  RETURN hivemind_postgrest_utilities.list_votes(_observer_id, _post_id, _limit,
    'bridge_list_by_comment_voter_after'::hivemind_postgrest_utilities.list_votes_case,
    'bridge_list_votes'::hivemind_postgrest_utilities.vote_presentation,
    _start_voter_id);
END
$$
;
