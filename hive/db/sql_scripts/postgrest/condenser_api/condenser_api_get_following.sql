DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_following;
CREATE FUNCTION hivemind_endpoints.condenser_api_get_following(IN _json_is_object BOOLEAN, IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
    _follow_args hivemind_postgrest_utilities.follow_arguments;
    _result JSONB;
BEGIN
    _follow_args := hivemind_postgrest_utilities.get_validated_follow_arguments(_params, _json_is_object);

SELECT COALESCE(
    jsonb_agg(
        jsonb_build_object(
            'following', followers.condenser_get_following,
            'follower',  _follow_args.account,
            'what', array[_follow_args.follow_type]
        )
    ),
    '[]'::jsonb
) AS _result
INTO _result
FROM (
    SELECT *
    FROM hivemind_app.condenser_get_following(
      _follow_args.account,
      _follow_args.start,
      _follow_args.converted_follow_type,
      _follow_args.limit
    )
) AS followers;

RETURN _result;

END;
$$
