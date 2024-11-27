DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_list_community_roles;
CREATE FUNCTION hivemind_endpoints.bridge_api_list_community_roles(IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_limit INT;
_last TEXT;
_community_id INT;
_last_role INT;

_result JSONB;
BEGIN
  _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"community": "string", "last": "string", "limit": "number"}', 1, NULL);

  _limit = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'limit', False);
  _limit = hivemind_postgrest_utilities.valid_number(_limit, 50, 1, 1000, 'limit');

  _last = hivemind_postgrest_utilities.valid_account(
    hivemind_postgrest_utilities.parse_argument_from_json(_params, 'last', False),
    True);
  
  _community_id = 
    hivemind_postgrest_utilities.find_community_id(
      hivemind_postgrest_utilities.valid_community(
        hivemind_postgrest_utilities.parse_argument_from_json(_params, 'community', True),
        False
      ),
    True);

  IF _last IS NOT NULL AND _last <> '' THEN
    SELECT INTO _last_role
      COALESCE(
        ( SELECT role_id 
          FROM hivemind_app.hive_roles
          WHERE account_id = (SELECT id from hivemind_app.hive_accounts WHERE name = _last)
          AND hivemind_app.hive_roles.community_id = _community_id
        ),
      0);
    
    IF _last_role = 0 THEN
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('invalid last');
    END IF;
  END IF;

  _result = (
    SELECT jsonb_agg( -- bridge_api_list_community_roles
      jsonb_build_array(row.name, row.role, row.title)
    ) FROM (
      SELECT
        ha.name,
        hivemind_postgrest_utilities.get_role_name(hr.role_id) AS role,
        hr.title
      FROM
        hivemind_app.hive_roles hr
      JOIN
        hivemind_app.hive_accounts ha ON hr.account_id = ha.id
      WHERE
        hr.community_id = _community_id
        AND hr.role_id <> 0 AND
        ( CASE
            WHEN _last_role IS NOT NULL THEN NOT (
              hr.role_id >= _last_role AND NOT (hr.role_id = _last_role AND ha.name > _last)
            )
            ELSE True
          END
        )
      ORDER BY
        hr.role_id DESC, ha.name
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;