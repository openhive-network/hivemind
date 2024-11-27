DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_list_all_subscriptions;
CREATE FUNCTION hivemind_endpoints.bridge_api_list_all_subscriptions(IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_account_id INT;
_result JSONB;
BEGIN
  _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"account": "string"}', 1, NULL);
  
  _account_id = hivemind_postgrest_utilities.find_account_id(
    hivemind_postgrest_utilities.valid_account(
      hivemind_postgrest_utilities.parse_argument_from_json(_params, 'account', True),
      False),
    True);

  _result = (
    SELECT jsonb_agg(  -- bridge_api_list_all_subscriptions
      jsonb_build_array(row.name, row.title, row.role, row.role_title)
    ) FROM (
      SELECT
        hc.name,
        hc.title,
        hivemind_postgrest_utilities.get_role_name(COALESCE(hr.role_id, 0)) AS role,
        COALESCE(hr.title, '') AS role_title
      FROM
        hivemind_app.hive_communities hc
      JOIN
        hivemind_app.hive_subscriptions hs ON hc.id = hs.community_id
      LEFT JOIN
        hivemind_app.hive_roles hr ON hr.account_id = hs.account_id AND hr.community_id = hc.id
      WHERE
        hs.account_id = _account_id
      ORDER BY
        COALESCE(hr.role_id, 0) DESC, hc.rank
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;