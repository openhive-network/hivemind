DROP FUNCTION IF EXISTS hivemind_utilities.valid_account;
CREATE OR REPLACE FUNCTION hivemind_utilities.valid_account(  
  _name TEXT, 
  _allow_empty BOOLEAN DEFAULT FALSE
)
  RETURNS TEXT
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
DECLARE
  name_segment TEXT := '[a-z][a-z0-9\-]+[a-z0-9]';
BEGIN
  IF _name IS NULL OR _name = '' THEN
    IF NOT _allow_empty THEN
      RAISE EXCEPTION '%', hivemind_utilities.invalid_account_exception('invalid account (not specified)');
    END IF;

    RETURN _name;
  END IF;

  IF LENGTH(_name) < 3 OR LENGTH(_name) > 16 THEN
      RAISE EXCEPTION '%', hivemind_utilities.invalid_account_exception('invalid account name length: ' || _name);
  END IF;

  IF SUBSTRING(_name FROM 1 FOR 1) = '@' THEN
    RAISE EXCEPTION '%', hivemind_utilities.invalid_account_exception('invalid account name char ''@''');
  END IF;

  IF _name ~ ('^'|| name_segment ||'(?:\.'|| name_segment ||')*$') THEN
    RETURN _name;
  ELSE
    RAISE EXCEPTION '%', hivemind_utilities.invalid_account_exception('invalid account char');
  END IF;
END;
$BODY$
;