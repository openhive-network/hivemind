DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.json_date;
CREATE FUNCTION hivemind_postgrest_utilities.json_date(_date TIMESTAMP DEFAULT NULL)
  RETURNS TEXT
  LANGUAGE plpgsql
  IMMUTABLE
AS
$BODY$
BEGIN
  IF _date IS NULL OR _date = '9999-12-31 23:59:59+00'::TIMESTAMP OR _date = 'infinity' THEN
      RETURN '1969-12-31T23:59:59';
  END IF;

  RETURN TO_CHAR(_date, 'YYYY-MM-DD') || 'T' || TO_CHAR(_date, 'HH24:MI:SS');

END;
$BODY$
;