DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.find_community_id CASCADE;
CREATE FUNCTION hivemind_postgrest_utilities.find_community_id(
  IN _community_name hivemind_app.hive_communities.name%TYPE,
  IN _check BOOLEAN
)
RETURNS INTEGER
LANGUAGE 'plpgsql' STABLE
AS
$function$
DECLARE
  _community_id INT = 0;
BEGIN
  IF (_community_name <> '') THEN
    SELECT INTO _community_id COALESCE( ( SELECT id FROM hivemind_app.hive_communities WHERE name=_community_name ), 0 );
    IF _check AND _community_id = 0 THEN
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Community ' || _community_name || ' does not exist');
    END IF;
  END IF;
  RETURN _community_id;
END
$function$
;