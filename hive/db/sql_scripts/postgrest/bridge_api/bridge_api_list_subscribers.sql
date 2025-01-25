DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_list_subscribers;
CREATE FUNCTION hivemind_endpoints.bridge_api_list_subscribers(IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
    _community_id INT;
    _community TEXT;
    _last_name TEXT;
    _limit INTEGER := 100;
BEGIN
    _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"community": "string", "last": "string", "limit": "number"}', 1, '{"community": "given community name is not valid"}');

    _community = hivemind_postgrest_utilities.parse_argument_from_json(_params, 'community', True);
    _community = hivemind_postgrest_utilities.valid_community(_community);
    _community_id = hivemind_postgrest_utilities.find_community_id(_community, True);

    _last_name = hivemind_postgrest_utilities.valid_account(
        hivemind_postgrest_utilities.parse_argument_from_json(_params, 'last', False),
        True
    );

    IF _last_name IS NOT NULL THEN
        PERFORM hivemind_postgrest_utilities.find_subscription_id(_last_name,  _community, True); -- Check that account exists and is subscribed to the community
    END IF;

    _limit = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'limit', False);
    _limit = hivemind_postgrest_utilities.valid_number(_limit, 100, 1, 100, 'limit');

    RETURN COALESCE(
      (
        SELECT jsonb_agg(jsonb_build_array(row.name, row.role, row.title, row.created_at)) FROM ( -- bridge_api_list_subscribers
          SELECT
            ha.name,
            hivemind_postgrest_utilities.get_role_name(COALESCE(hr.role_id,0)) AS role,
            COALESCE(hr.title, NULL) AS title,
            hivemind_postgrest_utilities.json_date(hs.created_at) AS created_at
          FROM hivemind_app.hive_subscriptions hs
          LEFT JOIN hivemind_app.hive_roles hr ON hs.account_id = hr.account_id
               AND hs.community_id = hr.community_id
          JOIN hivemind_app.hive_accounts ha ON hs.account_id = ha.id
          WHERE hs.community_id = _community_id
          AND (_last_name IS NULL OR ha.name COLLATE "C" > _last_name COLLATE "C")
          ORDER BY ha.name ASC
          LIMIT _limit
       ) row
      ),
      '[]'::JSONB
    );
END
$$;