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

BEGIN
  _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"author": "string","permlink":"string"}', 2, NULL);

  _author = hivemind_postgrest_utilities.parse_argument_from_json(_params, 'author', True);
  _permlink = hivemind_postgrest_utilities.valid_permlink(
    hivemind_postgrest_utilities.parse_argument_from_json(_params, 'permlink', True),
    False
  );

  _post_id = hivemind_postgrest_utilities.find_comment_id( _author, _permlink, True );

  RETURN COALESCE(
    (
      SELECT jsonb_agg(ha.name ORDER BY ha.name)
      FROM hivemind_app.hive_accounts ha
      JOIN hivemind_app.hive_reblogs hr ON ha.id = hr.blogger_id
      WHERE hr.post_id = _post_id
    )
    ,
    '[]'::jsonb
  );
END;
$$
;