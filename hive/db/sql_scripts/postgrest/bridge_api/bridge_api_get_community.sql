DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_community;
CREATE FUNCTION hivemind_endpoints.bridge_api_get_community(IN _json_is_object BOOLEAN, IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _community_id INT;
  _observer_id INT;
BEGIN
  PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"name","observer"}', '{"string", "string"}', 1);

  _community_id = 
    hivemind_postgrest_utilities.find_community_id(
      hivemind_postgrest_utilities.valid_community(
        hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'name', 0, True)
      ),
    True);
  
  _observer_id = 
    hivemind_postgrest_utilities.find_account_id(
      hivemind_postgrest_utilities.valid_account(
        hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'observer', 1, False),
      True),
    True);

  RETURN (
    SELECT to_jsonb(row) FROM (
      SELECT
        hc.id,
        hc.name,
        COALESCE(NULLIF(hc.title,''),CONCAT('@',hc.name))::VARCHAR(32) AS title,
        hc.about,
        hc.lang,
        hc.type_id,
        hc.is_nsfw,
        hc.subscribers,
        hc.created_at::VARCHAR(19),
        hc.sum_pending,
        hc.num_pending,
        hc.num_authors,
        hc.avatar_url,
        hc.description,
        hc.flag_text,
        hc.settings::JSONB,
        (
          CASE
            WHEN _observer_id <> 0 THEN hivemind_postgrest_utilities.get_community_context(_observer_id, _community_id)
            ELSE '{}'::JSONB
          END
        ) AS context,
        ( SELECT
            jsonb_agg(
              jsonb_build_array(a.name, hivemind_postgrest_utilities.get_role_name(r.role_id), r.title)
              ORDER BY r.role_id DESC, r.account_id DESC
            )
            FROM hivemind_app.hive_roles r
            JOIN hivemind_app.hive_accounts a ON r.account_id = a.id
            WHERE r.community_id = _community_id AND r.role_id BETWEEN 4 AND 8
        ) AS team
      FROM hivemind_app.hive_communities hc
      WHERE hc.id = _community_id
      GROUP BY hc.id
    ) row
  );
END
$$
;