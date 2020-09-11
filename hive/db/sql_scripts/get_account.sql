DROP FUNCTION IF EXISTS get_account(character varying, boolean);

CREATE OR REPLACE FUNCTION get_account(
  in _account hive_accounts.name%TYPE,
  in _check boolean)
RETURNS INT
LANGUAGE 'plpgsql'
AS
$function$
DECLARE 
  account_id INT;
BEGIN
  SELECT INTO account_id COALESCE( ( SELECT id FROM hive_accounts WHERE name=_account ), 0 );
  IF _check AND account_id = 0 THEN
    RAISE EXCEPTION 'Account % does not exist', _account;
  END IF;

  RETURN account_id;
END
$function$
;