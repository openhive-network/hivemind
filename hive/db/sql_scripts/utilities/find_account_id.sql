DROP FUNCTION IF EXISTS hivemind_utilities.find_account_id;
CREATE OR REPLACE FUNCTION hivemind_utilities.find_account_id(
  in _account hivemind_app.hive_accounts.name%TYPE,
  in _check boolean)
RETURNS INT
LANGUAGE 'plpgsql'
AS
$function$
DECLARE
  _account_id INT = 0;
BEGIN
  IF (_account <> '') THEN
    SELECT INTO _account_id COALESCE( ( SELECT id FROM hivemind_app.hive_accounts WHERE name=_account ), 0 );
    IF _check AND _account_id = 0 THEN
      RAISE EXCEPTION '%', hivemind_utilities.invalid_account_exception('Account ' || _account || ' does not exist');
    END IF;
  END IF;
  RETURN _account_id;
END
$function$
;