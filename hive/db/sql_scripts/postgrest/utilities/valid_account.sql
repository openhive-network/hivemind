DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.valid_account;
CREATE FUNCTION hivemind_postgrest_utilities.valid_account(
  _name TEXT, 
  _allow_empty BOOLEAN DEFAULT FALSE
)
  RETURNS TEXT
  LANGUAGE plpgsql
  IMMUTABLE
AS
$BODY$
DECLARE
  error_message TEXT;
BEGIN
  error_message = hivemind_postgrest_utilities.valid_account_no_exception(_name, _allow_empty);

  IF error_message <> _name THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.invalid_account_exception(error_message);
  END IF;

  RETURN _name;
END;
$BODY$
;