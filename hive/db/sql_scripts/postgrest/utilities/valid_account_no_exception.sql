DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.valid_account_no_exception;
CREATE FUNCTION hivemind_postgrest_utilities.valid_account_no_exception(
  _name TEXT,
  _allow_empty BOOLEAN DEFAULT FALSE
)
  RETURNS TEXT
  LANGUAGE plpgsql
  IMMUTABLE
AS
$BODY$
DECLARE
  name_segment TEXT := '[a-z][a-z0-9\-]+[a-z0-9]';
BEGIN
  IF _name IS NULL OR _name = '' THEN
    IF NOT _allow_empty THEN
      RETURN 'invalid account (not specified)';
    END IF;

    RETURN _name;
  END IF;

  IF LENGTH(_name) NOT BETWEEN 3 AND 16 THEN
    RETURN 'invalid account name length: `' || _name || '`';
  END IF;

  IF LEFT(_name, 1) = '@' THEN
    RETURN 'invalid account name char `@`';
  END IF;

  IF _name ~ ('^'|| name_segment ||'(?:\.'|| name_segment ||')*$') THEN
    RETURN _name;
  ELSE
    RETURN 'invalid account char';
  END IF;
END;
$BODY$
;