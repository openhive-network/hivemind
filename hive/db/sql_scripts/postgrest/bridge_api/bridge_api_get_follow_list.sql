DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_follow_list;
CREATE FUNCTION hivemind_endpoints.bridge_api_get_follow_list(IN _json_is_object BOOLEAN, IN _params JSONB)
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
  PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"observer", "follow_type"}', '{"string", "string"}', 1);

  _observer_id = hivemind_postgrest_utilities.find_account_id(
    hivemind_postgrest_utilities.valid_account(
      hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'observer', 0, True), True),
    True);

  CASE hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'follow_type', 1, False)
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
      WITH np AS (
        SELECT 
          ha.name,
          hivemind_postgrest_utilities.extract_profile_metadata(ha.json_metadata, ha.posting_json_metadata)->'profile' AS profile
        FROM
          hivemind_app.hive_follows hf
        JOIN
          hivemind_app.hive_accounts ha ON ha.id = hf.following
        WHERE
          hf.follower = _observer_id AND
          (CASE WHEN _follow_muted THEN hf.follow_muted ELSE hf.follow_blacklists END)
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
      SELECT jsonb_agg (
        jsonb_build_object(
          'name', row.name,
          'blacklist_description', to_jsonb(''::TEXT),
          'muted_list_description', to_jsonb(''::TEXT)
        )
      ) FROM (
          SELECT
            ha.name
          FROM
            hivemind_app.hive_follows hf
          JOIN
            hivemind_app.hive_accounts ha ON ha.id = hf.following
          WHERE
            hf.follower = _observer_id AND
            (CASE WHEN _follow_muted THEN hf.state = 2 ELSE hf.blacklisted END)
          ORDER BY ha.name
        ) row
  );
  END IF;

  IF _result IS NULL THEN
    _result = '[]'::jsonb;
  END IF;

  RETURN _result;
END
$$
;