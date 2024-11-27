DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_reblogged_by;
CREATE FUNCTION hivemind_endpoints.condenser_api_get_reblogged_by(IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _author TEXT;
  _permlink TEXT;
  _post_id INT;
  _account_id INT;

BEGIN
  _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"author": "string","permlink":"string"}', 2, NULL);
  _author = hivemind_postgrest_utilities.parse_argument_from_json(_params, 'author', True);
  _permlink = hivemind_postgrest_utilities.parse_argument_from_json(_params, 'permlink', True);
  _account_id = hivemind_postgrest_utilities.find_account_id( hivemind_postgrest_utilities.valid_account(_author, False), True );
  _post_id = hivemind_postgrest_utilities.find_comment_id( _author, hivemind_postgrest_utilities.valid_permlink(_permlink, False), True );

  RETURN COALESCE(
    (
      SELECT jsonb_agg(ha.name ORDER BY ha.name)
      FROM hivemind_app.hive_accounts ha
      JOIN hivemind_app.hive_feed_cache hfc ON ha.id = hfc.account_id
      WHERE hfc.post_id = _post_id AND ha.id <> _account_id
    )
    ,
    '[]'::jsonb
  );
END;
$$
;