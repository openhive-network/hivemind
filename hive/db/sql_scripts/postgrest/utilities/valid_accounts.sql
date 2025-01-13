DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.valid_accounts;
CREATE FUNCTION hivemind_postgrest_utilities.valid_accounts(
  _names TEXT[],
  _allow_empty BOOLEAN DEFAULT FALSE
)
  RETURNS TEXT[]
  LANGUAGE plpgsql
  IMMUTABLE
AS
$BODY$
DECLARE
  name_segment TEXT := '[a-z][a-z0-9\-]+[a-z0-9]';
  _name TEXT;
  _errors JSONB := '[]'::jsonb;
  _error_message TEXT;
BEGIN
  FOREACH _name IN ARRAY _names
  LOOP
    BEGIN
      IF _name IS NULL OR _name = '' THEN
        IF NOT _allow_empty THEN
          _errors := _errors || jsonb_build_object(_name, 'invalid account (not specified)');
          CONTINUE;
        END IF;
      END IF;

      IF LENGTH(_name) NOT BETWEEN 3 AND 16 THEN
        _errors := _errors || jsonb_build_object(_name, 'invalid account name length: `' || _name || '`');
        CONTINUE;
      END IF;

      IF LEFT(_name, 1) = '@' THEN
        _errors := _errors || jsonb_build_object(_name, 'invalid account name char `@`');
        CONTINUE;
      END IF;

      IF NOT _name ~ ('^'|| name_segment ||'(?:\.'|| name_segment ||')*$') THEN
        _errors := _errors || jsonb_build_object(_name, 'invalid account char');
        CONTINUE;
      END IF;

    END;
  END LOOP;

  IF jsonb_array_length(_errors) > 0 THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.invalid_account_exception(_errors::TEXT);
  END IF;

  RETURN _names;
END;
$BODY$;
