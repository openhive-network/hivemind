DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.json_date;
-- STABLE like to_char, and a single expression, so the planner inlines it into its callers
CREATE FUNCTION hivemind_postgrest_utilities.json_date(_date TIMESTAMP DEFAULT NULL)
  RETURNS TEXT
  LANGUAGE sql
  STABLE
AS
$BODY$
  SELECT CASE
    WHEN _date IS NULL OR _date = '9999-12-31 23:59:59'::TIMESTAMP OR _date = 'infinity'::TIMESTAMP
      THEN '1969-12-31T23:59:59'
    ELSE TO_CHAR(_date, 'YYYY-MM-DD"T"HH24:MI:SS')
  END
$BODY$
;
