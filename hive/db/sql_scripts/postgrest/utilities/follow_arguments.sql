-- By enclosing `limit` in double quotes, we ensure SQL compatibility
-- while maintaining naming consistency with the API parameters.
DROP TYPE IF EXISTS hivemind_postgrest_utilities.follow_arguments CASCADE;
CREATE TYPE hivemind_postgrest_utilities.follow_arguments AS (
    account TEXT,
    start TEXT,
    follow_type TEXT,
    converted_follow_type INT,
    "limit" INT
);

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_validated_follow_arguments;
CREATE FUNCTION hivemind_postgrest_utilities.get_validated_follow_arguments(
    _params JSON,
    _json_is_object BOOLEAN
) RETURNS hivemind_postgrest_utilities.follow_arguments AS $$
DECLARE
    _follow_args hivemind_postgrest_utilities.follow_arguments;
BEGIN
    -- account
    _follow_args.account := hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'account', 0, True);
    _follow_args.account := hivemind_postgrest_utilities.valid_account(_follow_args.account, False);

    -- start
    _follow_args.start := COALESCE(hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'start', 1, False), '');
    _follow_args.start := hivemind_postgrest_utilities.valid_account(_follow_args.start, True);

    -- follow_type
    _follow_args.follow_type := COALESCE(hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'follow_type', 2, False), 'blog');
    _follow_args.converted_follow_type := hivemind_postgrest_utilities.valid_follow_type(_follow_args.follow_type);

    -- limit
    _follow_args.limit := hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'limit', 3, False);
    _follow_args.limit := hivemind_postgrest_utilities.valid_number(_follow_args.limit, 1000, 1, 1000, 'limit');

    RETURN _follow_args;
END;
$$ LANGUAGE plpgsql;
