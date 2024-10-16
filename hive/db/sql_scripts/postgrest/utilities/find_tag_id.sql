DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.find_tag_id;
CREATE FUNCTION hivemind_postgrest_utilities.find_tag_id(IN _tag_name TEXT, IN _check BOOLEAN)
RETURNS INTEGER
LANGUAGE 'plpgsql' STABLE
AS
$function$
DECLARE
  _tag_id INT = 0;
BEGIN
  IF _tag_name IS NOT NULL AND (_tag_name <> '') THEN
    SELECT INTO _tag_id COALESCE( ( SELECT id FROM hivemind_app.hive_tag_data WHERE tag=_tag_name ), 0 );
    IF _check AND _tag_id = 0 THEN
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_tag_not_exists_exception(_tag_name);
    END IF;
  END IF;
  RETURN _tag_id;
END
$function$
;