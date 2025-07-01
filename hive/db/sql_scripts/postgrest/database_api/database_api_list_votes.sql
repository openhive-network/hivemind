DROP FUNCTION IF EXISTS hivemind_endpoints.database_api_list_votes;
CREATE FUNCTION hivemind_endpoints.database_api_list_votes(IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _start JSONB;
  _limit INT;
  _order TEXT;

  _order_by_comment_voter BOOLEAN;
  _voter TEXT;
  _author TEXT;
  _observer TEXT;
  _permlink TEXT;

  _voter_id INT;
  _observer_id INT;
  _post_id INT;
BEGIN
  _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"start": "array", "limit": "number", "order": "string", "observer": "string"}', 3, NULL);
  _start = hivemind_postgrest_utilities.parse_argument_from_json(_params, 'start', True);
  _limit = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'limit', False);
  _order = hivemind_postgrest_utilities.parse_argument_from_json(_params, 'order', True);
  _observer = hivemind_postgrest_utilities.parse_argument_from_json(_params, 'observer', False);
  _observer_id = hivemind_postgrest_utilities.find_account_id(
    hivemind_postgrest_utilities.valid_account(_observer, True),
    False);

  _order = lower(_order);

  IF _order = 'by_comment_voter' THEN
    _order_by_comment_voter = True;
  ELSIF _order = 'by_voter_comment' THEN
    _order_by_comment_voter = False;
  ELSE
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Unsupported order, valid orders: by_comment_voter, by_voter_comment');
  END IF;

  _limit = hivemind_postgrest_utilities.valid_number(_limit, 1000, 1, 1000, 'limit');

  IF _order_by_comment_voter THEN
    IF jsonb_array_length(_start) <> 3 THEN
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Expecting 3 arguments in ''start'' array: post author and permlink, optional page start voter');
    END IF;
    _author = hivemind_postgrest_utilities.valid_account(_start->>0, False);
    _permlink = hivemind_postgrest_utilities.valid_permlink(_start->>1, False);
    _voter = hivemind_postgrest_utilities.valid_account(_start->>2, True);
  ELSE
    IF jsonb_array_length(_start) <> 3 THEN
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Expecting 3 arguments in ''start'' array: voter, optional page start author and permlink');
    END IF;
    _voter = hivemind_postgrest_utilities.valid_account(_start->>0, False);
    _author = hivemind_postgrest_utilities.valid_account(_start->>1, True);
    _permlink = hivemind_postgrest_utilities.valid_permlink(_start->>2, True);
  END IF;

  _post_id = hivemind_postgrest_utilities.find_comment_id( _author, _permlink, True);
  _voter_id = hivemind_postgrest_utilities.find_account_id(_voter, True);

  IF _order_by_comment_voter THEN
    RETURN jsonb_build_object('votes', (hivemind_postgrest_utilities.list_votes(_observer_id, _post_id, _limit, 'database_list_by_comment_voter'::hivemind_postgrest_utilities.list_votes_case, 'database_api'::hivemind_postgrest_utilities.vote_presentation, _voter_id)));
  ELSE
    RETURN jsonb_build_object('votes', (hivemind_postgrest_utilities.list_votes(_observer_id, _post_id, _limit, 'database_list_by_voter_comment'::hivemind_postgrest_utilities.list_votes_case, 'database_api'::hivemind_postgrest_utilities.vote_presentation, _voter_id)));
  END IF;
END;
$$
;
