DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_followers;
CREATE FUNCTION hivemind_endpoints.condenser_api_get_followers(IN _json_is_object BOOLEAN, IN _params JSONB)
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
            'following', _follow_args.account,
            'follower', followers.condenser_get_followers,
            'what', array[_follow_args.follow_type]
        )
    ),
    '[]'::jsonb
) AS _result
INTO _result
FROM (
    SELECT *
    FROM hivemind_app.condenser_get_followers(
      _follow_args.account,
      _follow_args.start,
      _follow_args.converted_follow_type,
      _follow_args.limit
    )
) AS followers;

RETURN _result;

END;
$$
