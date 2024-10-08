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
    _result = COALESCE(_result, '[]'::jsonb) || json_build_object(
      'id', _vote->'id',
      'voter', _vote->>'voter',
      'author', _vote->>'author',
      'permlink', _vote->>'permlink',
      'weight', _vote->'weight',
      'rshares', _vote->'rshares',
      'vote_percent', _vote->'percent',
      'last_update', hivemind_postgrest_utilities.json_date(to_timestamp(_vote->>'last_update', 'YYYY-MM-DD"T"HH24:MI:SS')),
      'num_changes', _vote->'num_changes'
    )::jsonb;
  ELSIF _presentation_mode = 'bridge_api' THEN
    _result = COALESCE(_result, '[]'::jsonb) || json_build_object(
      'rshares', _vote->'rshares',
      'voter', _vote->>'voter'
    )::jsonb;
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

DROP TYPE IF EXISTS hivemind_postgrest_utilities.list_votes_case CASCADE;
CREATE TYPE hivemind_postgrest_utilities.list_votes_case AS ENUM( 'create_post', 'database_list_by_comment_voter', 'database_list_by_voter_comment');

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.list_votes;
CREATE FUNCTION hivemind_postgrest_utilities.list_votes(IN _author TEXT, IN _permlink TEXT, IN _limit INT, IN _case hivemind_postgrest_utilities.list_votes_case, IN _presentation_mode hivemind_postgrest_utilities.vote_presentation, IN _voter TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS
$function$
DECLARE
_post_id INT;
_voter_id INT;
_result JSONB;
BEGIN
  IF _case = ANY(ARRAY['database_list_by_comment_voter'::hivemind_postgrest_utilities.list_votes_case,'database_list_by_voter_comment'::hivemind_postgrest_utilities.list_votes_case]) THEN
    assert _voter IS NOT NULL;
    _voter_id = hivemind_postgrest_utilities.find_account_id(_voter, True);
  END IF;

  _post_id =  hivemind_postgrest_utilities.find_comment_id( _author, _permlink, True);
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
          (
            CASE
              WHEN _case = 'create_post' THEN v.post_id = _post_id
              WHEN _case = 'database_list_by_comment_voter' THEN (v.post_id = _post_id AND v.voter_id >= _voter_id)
              WHEN _case = 'database_list_by_voter_comment' THEN (v.voter_id = _voter_id AND v.post_id >= _post_id)
              END
          )
        ORDER BY
          (
            CASE
              WHEN _case = 'create_post' THEN v.voter_id
              WHEN _case = 'database_list_by_comment_voter' THEN v.voter_id
              WHEN _case = 'database_list_by_voter_comment' THEN v.post_id
              END
          )
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