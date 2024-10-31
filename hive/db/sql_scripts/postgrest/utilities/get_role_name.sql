DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_role_name;
CREATE OR REPLACE FUNCTION hivemind_postgrest_utilities.get_role_name(in _role_id INT)
RETURNS TEXT
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$function$
BEGIN
  CASE _role_id
    WHEN -2 THEN RETURN 'muted';
    WHEN 0 THEN RETURN 'guest';
    WHEN 2 THEN RETURN 'member';
    WHEN 4 THEN RETURN 'mod';
    WHEN 6 THEN RETURN 'admin';
    WHEN 8 THEN RETURN 'owner';
    ELSE RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('role id not found');
  END CASE;
END
$function$
;