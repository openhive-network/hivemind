DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_list_subscribers;
CREATE FUNCTION hivemind_endpoints.bridge_api_list_subscribers(IN _json_is_object BOOLEAN, IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
    _community_id INT;
    _community TEXT;
    _subscription_id INT;
    _limit INTEGER := 100;
BEGIN
    PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"community", "last", "limit"}', '{"string", "string", "number"}', 1);

    _community = hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'community', 0, True);
    _community = hivemind_postgrest_utilities.valid_community(_community);
    _community_id = hivemind_postgrest_utilities.find_community_id(_community, True);

    _subscription_id =
      hivemind_postgrest_utilities.find_subscription_id(
        hivemind_postgrest_utilities.valid_account(
          hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'last', 1, False),
          True),
        _community,
        True);

    _limit = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'limit', 2, False);
    _limit = hivemind_postgrest_utilities.valid_number(_limit, 100, 1, 100, 'limit');

    RETURN COALESCE(
      (
        SELECT jsonb_agg(jsonb_build_array(row.name, row.role, row.title, row.created_at)) FROM (
          SELECT
            ha.name,
            hivemind_postgrest_utilities.get_role_name(COALESCE(hr.role_id,0)) AS role,
            COALESCE(hr.title, NULL) AS title,
            hivemind_postgrest_utilities.json_date(hs.created_at) AS created_at
          FROM hivemind_app.hive_subscriptions hs
          JOIN hivemind_app.hive_accounts ha ON hs.account_id = ha.id
          LEFT JOIN hivemind_app.hive_roles hr ON hs.account_id = hr.account_id AND hs.community_id = hr.community_id
          WHERE
            hs.community_id = _community_id
            AND NOT (_subscription_id <> 0 AND hs.id >= _subscription_id)
          ORDER BY ha.name ASC
          LIMIT _limit
        ) row
      ),
      '[]'::JSONB
    );
END
$$
;