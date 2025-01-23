DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_follow_list;
CREATE FUNCTION hivemind_endpoints.bridge_api_get_follow_list(IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_observer_id INT;
_follow_type_flag INT;
_follow_muted BOOLEAN; -- if false then type is blacklist
_get_blacklists BOOLEAN; -- if follow_blacklist/muted
_result JSONB;

BEGIN
  _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"observer": "string", "follow_type": "string"}', 1, NULL);

  _observer_id = hivemind_postgrest_utilities.find_account_id(
    hivemind_postgrest_utilities.valid_account(
      hivemind_postgrest_utilities.parse_argument_from_json(_params, 'observer', True), True),
    True);

  CASE hivemind_postgrest_utilities.parse_argument_from_json(_params, 'follow_type', False)
    WHEN NULL then
      _get_blacklists = False;
      _follow_muted = False;
    WHEN 'blacklisted' THEN
      _get_blacklists = False;
      _follow_muted = False;
    WHEN 'follow_blacklist' THEN
      _get_blacklists = True;
      _follow_muted = False;
    WHEN 'muted' THEN
      _get_blacklists = False;
      _follow_muted = True;
    WHEN 'follow_muted' THEN
      _get_blacklists = True;
      _follow_muted = True;
    ELSE RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Unsupported follow_type, valid values: blacklisted, follow_blacklist, muted, follow_muted');
  END CASE;

  IF _get_blacklists THEN
    _result = (
      WITH np AS ( -- bridge_api_get_follow_list with _get_blacklists
        SELECT
          ha.name,
          hivemind_postgrest_utilities.extract_profile_metadata(ha.json_metadata, ha.posting_json_metadata)->'profile' AS profile
        FROM
          hivemind_app.follow_muted AS fm
        JOIN
          hivemind_app.hive_accounts ha ON ha.id = fm.following
        WHERE
          fm.follower = _observer_id AND _follow_muted
        UNION ALL
        SELECT
          ha.name,
          hivemind_postgrest_utilities.extract_profile_metadata(ha.json_metadata, ha.posting_json_metadata)->'profile' AS profile
        FROM
          hivemind_app.follow_blacklisted AS fb
        JOIN
          hivemind_app.hive_accounts ha ON ha.id = fb.following
        WHERE
          fb.follower = _observer_id AND NOT _follow_muted
        )
      SELECT jsonb_agg(
        jsonb_build_object(
          'name', ordered_np.name,
          'blacklist_description', ordered_np.profile->>'blacklist_description',
          'muted_list_description', ordered_np.profile->>'muted_list_description'
        )
      ) FROM ( SELECT * FROM np ORDER BY np.name ) ordered_np
    );
  ELSE
    _result = (
      SELECT jsonb_agg ( -- bridge_api_get_follow_list without _get_blacklists
        jsonb_build_object(
          'name', row.name,
          'blacklist_description', to_jsonb(''::TEXT),
          'muted_list_description', to_jsonb(''::TEXT)
        )
      ) FROM (
          SELECT ha.name
          FROM hivemind_app.muted AS m
          JOIN hivemind_app.hive_accounts ha ON ha.id = m.following
          WHERE m.follower = _observer_id AND _follow_muted
          UNION ALL
          SELECT ha.name
          FROM hivemind_app.blacklisted AS b
          JOIN hivemind_app.hive_accounts ha ON ha.id = b.following
          WHERE b.follower = _observer_id AND NOT _follow_muted
          ORDER BY name
        ) row
  );
  END IF;

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;
