DROP FUNCTION IF EXISTS hivemind_endpoints.database_api_find_votes;
CREATE FUNCTION hivemind_endpoints.database_api_find_votes(IN _json_is_object BOOLEAN, IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _vote_args hivemind_postgrest_utilities.vote_arguments;
  _result JSONB;
BEGIN
  _vote_args := hivemind_postgrest_utilities.get_validated_vote_arguments(_params, _json_is_object);

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

  FROM (SELECT * FROM hivemind_app.find_votes(_vote_args.author, _vote_args.permlink, 1000)) AS votes;

  RETURN _result;
END;
$$
;