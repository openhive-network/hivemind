DROP FUNCTION IF EXISTS hivemind_endpoints.database_api_find_votes;
CREATE FUNCTION hivemind_endpoints.database_api_find_votes(IN _json_is_object BOOLEAN, IN _params JSON)
RETURNS JSON
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _author TEXT;
  _permlink TEXT;
  _result JSON;
BEGIN
  _author = hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'author', 0, True);
  _author = hivemind_postgrest_utilities.valid_account(_author, False);

  _permlink = hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'permlink', 1, True);
  _permlink = hivemind_postgrest_utilities.valid_permlink(_permlink, False);

  PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"author","permlink"}', '{"string","string"}');

  SELECT jsonb_build_object(
    'votes', COALESCE(jsonb_agg(
      jsonb_build_object(
        'id', votes.id,
        'voter', votes.voter,
        'author', votes.author,
        'weight', votes.weight,
        'vote_percent', votes.percent,
        'rshares', votes.rshares,
        'permlink', votes.permlink,
        'last_update', votes.last_update,
        'num_changes', votes.num_changes
      )), '[]'::jsonb)
  ) AS _result INTO _result

  FROM (SELECT * FROM hivemind_app.find_votes(_author, _permlink, 1000)) AS votes;

  RETURN _result;
END;
$$
;