DROP TYPE IF EXISTS hivemind_postgrest_utilities.vote_presentation CASCADE;
CREATE TYPE hivemind_postgrest_utilities.vote_presentation AS ENUM( 'database_api', 'condenser_api', 'bridge_api', 'active_votes');

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.create_votes_json_array;
CREATE FUNCTION hivemind_postgrest_utilities.create_votes_json_array(IN _votes JSONB, IN _presentation_mode hivemind_postgrest_utilities.vote_presentation)
RETURNS JSONB
LANGUAGE plpgsql
IMMUTABLE
AS
$function$
DECLARE
_vote JSONB;
_result JSONB;
BEGIN
FOR _vote IN SELECT * FROM jsonb_array_elements(_votes) LOOP
  IF _presentation_mode = 'condenser_api' THEN
    _result = COALESCE(_result, '[]'::jsonb) || json_build_object(
      'percent', _vote->>'percent',
      'reputation', _vote->'reputation',
      'rshares', _vote->'rshares',
      'voter', _vote->>'voter'
    )::jsonb;
  ELSIF _presentation_mode = 'database_api' THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('create_votes_json_array for database_api not implemented');
  ELSIF _presentation_mode = 'bridge_api' THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('create_votes_json_array for bridge_api not implemented');
  ELSIF _presentation_mode = 'active_votes' THEN
    _result = COALESCE(_result, '[]'::jsonb) || json_build_object(
      'percent', _vote->'percent',
      'reputation', _vote->'reputation',
      'rshares', _vote->'rshares',
      'voter', _vote->>'voter',
      'time', hivemind_postgrest_utilities.json_date(to_timestamp(_vote->>'last_update', 'YYYY-MM-DD"T"HH24:MI:SS')),
      'weight', _vote->'weight'
    )::jsonb;
  ELSE
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('create_votes_json_array - unspecified vote presentation mode');
  END IF;
END LOOP;
RETURN _result;
END;
$function$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.list_votes;
CREATE FUNCTION hivemind_postgrest_utilities.list_votes(IN _author TEXT, IN _permlink TEXT, IN _limit INT, IN _presentation_mode hivemind_postgrest_utilities.vote_presentation)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS
$function$
DECLARE
_post_id INT;
_result JSONB;
BEGIN
  _post_id = hivemind_app.find_comment_id( _author, _permlink, True);
  _result = hivemind_postgrest_utilities.create_votes_json_array(
    ( 
      SELECT jsonb_agg(row_to_json( r )) FROM (
        SELECT 
          v.id,
          v.voter,
          v.author,
          v.permlink,
          v.weight,
          v.rshares,
          v.percent,
          v.last_update,
          v.num_changes,
          v.reputation
        FROM
          hivemind_app.hive_votes_view v
        WHERE
          v.post_id = _post_id
        ORDER BY
          voter_id
      LIMIT _limit
    ) r ),
    _presentation_mode
  );

  IF _result IS NULL THEN
    RETURN '[]'::jsonb;
  ELSE
    RETURN _result;
  END IF;
END;
$function$
;




    