-- after finish rewrite all api methods to sql, move all metods from the `hivemind_postgrest_utilities` schema to the `hivemin_app` schema.
DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.find_account_id;
CREATE FUNCTION hivemind_postgrest_utilities.find_account_id(
  in _account hivemind_app.hive_accounts.name%TYPE,
  in _check boolean)
RETURNS INT
LANGUAGE 'plpgsql' STABLE
AS
$function$
DECLARE
  _account_id INT = -1;
BEGIN
  IF (_account <> '') THEN
    SELECT INTO _account_id COALESCE( ( SELECT id FROM hivemind_app.hive_accounts WHERE name=_account ), -1 );
    IF _check AND _account_id = -1 THEN
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.invalid_account_exception('Account ' || _account || ' does not exist');
    END IF;
  END IF;
  RETURN _account_id;
END
$function$
;