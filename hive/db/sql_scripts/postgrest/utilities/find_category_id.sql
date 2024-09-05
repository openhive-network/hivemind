DROP FUNCTION IF EXISTS hivemind_utilities.find_category_id CASCADE;
CREATE FUNCTION hivemind_utilities.find_category_id(
    in _category_name hivemind_app.hive_category_data.category%TYPE,
    in _allow_empty BOOLEAN
)
RETURNS INTEGER
LANGUAGE 'plpgsql' STABLE
AS
$function$
DECLARE
  _category_id INT = 0;
BEGIN
  IF (_category_name <> '') THEN
    SELECT INTO _category_id COALESCE( ( SELECT id FROM hivemind_app.hive_category_data WHERE category=_category_name ), 0 );
    IF _allow_empty AND _category_id = 0 THEN
      RAISE EXCEPTION '%', hivemind_utilities.raise_category_not_exists_exception(_category_name);
    END IF;
  END IF;
  RETURN _category_id;
END
$function$
;