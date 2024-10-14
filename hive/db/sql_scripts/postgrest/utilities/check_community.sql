DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.check_community;
CREATE OR REPLACE FUNCTION hivemind_postgrest_utilities.check_community(_name TEXT)
  RETURNS BOOLEAN
  LANGUAGE plpgsql
  IMMUTABLE
AS
$BODY$
BEGIN
  IF _name IS NOT NULL AND
    LENGTH(_name) > 5 AND
    SUBSTRING(_name FROM 1 FOR 5) = 'hive-' AND
    SUBSTRING('hive-2123456' FROM 6 FOR 1) IN ('1', '2', '3') AND
    _name ~ '^hive-[123]\d{4,6}$' THEN

    RETURN TRUE;
  ELSE

    RETURN FALSE;
  END IF;
END;
$BODY$
;