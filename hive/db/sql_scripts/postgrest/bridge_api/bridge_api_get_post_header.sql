DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_posts_header;
CREATE FUNCTION hivemind_endpoints.bridge_api_get_posts_header(IN _params JSONB)
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
  _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"author": "string", "permlink": "string"}', 2, '{"permlink": "permlink must be string"}');
  _author = hivemind_postgrest_utilities.parse_argument_from_json(_params, 'author', True);
  _permlink = hivemind_postgrest_utilities.parse_argument_from_json(_params, 'permlink', True);
  
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