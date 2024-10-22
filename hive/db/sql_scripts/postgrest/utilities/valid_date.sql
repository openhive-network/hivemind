DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.valid_date;
CREATE OR REPLACE FUNCTION hivemind_postgrest_utilities.valid_date(
  _date TEXT,
  _allow_empty BOOLEAN
)
  RETURNS VOID
  LANGUAGE plpgsql
  IMMUTABLE
AS
$BODY$
BEGIN
  IF _date IS NULL OR _date = '' THEN
    IF NOT _allow_empty THEN
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Date is blank');
    END IF;
  ELSE
    IF _date ~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$' OR
       _date ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$' THEN

      BEGIN
        PERFORM to_timestamp(_date, 'YYYY-MM-DD HH24:MI:SS');
        RETURN;
        EXCEPTION WHEN others THEN
          NULL;
      END;

      BEGIN
        PERFORM to_timestamp(_date, 'YYYY-MM-DD"T"HH24:MI:SS');
        RETURN;
          EXCEPTION WHEN others THEN
        RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Date should be in format Y-m-d H:M:S or Y-m-dTH:M:S');
      END;
    ELSE
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Date should be in format Y-m-d H:M:S or Y-m-dTH:M:S');
    END IF;
  END IF;
END;
$BODY$
;