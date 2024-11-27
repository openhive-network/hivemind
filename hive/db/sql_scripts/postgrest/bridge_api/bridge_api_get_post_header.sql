DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_posts_header;
CREATE FUNCTION hivemind_endpoints.bridge_api_get_posts_header(IN _json_is_object BOOLEAN, IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_author TEXT;
_permlink TEXT;
_result JSONB;
BEGIN
  PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"author","permlink"}', '{"string","string"}');
  _author = hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'author', 0, True);
  _permlink = hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'permlink', 1, True);
  
  _author = hivemind_postgrest_utilities.valid_account(_author, False);
  _permlink = hivemind_postgrest_utilities.valid_permlink(_permlink, False);

  SELECT jsonb_build_object(
    'author', row.author,
    'permlink', row.permlink,
    'category', (CASE WHEN row.category IS NULL THEN '' ELSE row.category END),
    'depth', row.depth
  ) FROM (
      SELECT  -- bridge_api_get_posts_header
        ha_a.name as author, hpd_p.permlink as permlink, hcd.category as category, depth
      FROM 
        hivemind_app.hive_posts hp
      JOIN hivemind_app.hive_accounts ha_a ON ha_a.id = hp.author_id
      JOIN hivemind_app.hive_permlink_data hpd_p ON hpd_p.id = hp.permlink_id
      LEFT JOIN hivemind_app.hive_category_data hcd ON hcd.id = hp.category_id
      WHERE
        ha_a.name = _author AND hpd_p.permlink = _permlink AND counter_deleted = 0
  ) row INTO _result;

  IF _result IS NULL THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Post ' || _author || '/' || _permlink || ' does not exist');
  ELSE
    RETURN _result;
  END IF;
END
$$
;