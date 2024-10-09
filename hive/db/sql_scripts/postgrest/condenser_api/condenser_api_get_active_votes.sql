DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_active_votes;
CREATE FUNCTION hivemind_endpoints.condenser_api_get_active_votes(IN _json_is_object BOOLEAN, IN _params JSONB)
RETURNS JSON
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _vote_args hivemind_postgrest_utilities.vote_arguments;
  _result JSON;
BEGIN
  _vote_args := hivemind_postgrest_utilities.get_validated_vote_arguments(_params, _json_is_object);

  SELECT COALESCE(jsonb_agg(
      jsonb_build_object(
        'voter', votes.voter,
        'weight', votes.weight,
        'rshares', votes.rshares,
        'percent', votes.percent,
        'reputation', votes.reputation,
        'time', votes.last_update
      )), '[]'::jsonb) AS _result INTO _result

  FROM (SELECT * FROM hivemind_app.find_votes(_vote_args.author, _vote_args.permlink, 1000)) AS votes;

  RETURN _result;
END;
$$
;