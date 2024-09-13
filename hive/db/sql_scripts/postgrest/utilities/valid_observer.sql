DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.valid_observer;
CREATE OR REPLACE FUNCTION hivemind_postgrest_utilities.valid_observer(
  _observer TEXT, 
  _allow_empty BOOLEAN DEFAULT FALSE --zezwalaj na puste
)
  RETURNS TEXT
  LANGUAGE plpgsql
  IMMUTABLE
AS
$BODY$
DECLARE
  result TEXT;
BEGIN
  IF _observer = '' THEN
    RETURN _observer;
  ELSE
    result = hivemind_postgrest_utilities.valid_account_no_exception(_observer);
    IF result <> _observer THEN
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.invalid_account_exception('invalid account name type');
    ELSE
      RETURN _observer;
    END IF;
  END If;

END;
$BODY$
;