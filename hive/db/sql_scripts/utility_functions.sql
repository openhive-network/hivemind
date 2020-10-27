DROP FUNCTION IF EXISTS find_comment_id(character varying, character varying, boolean)
;
CREATE OR REPLACE FUNCTION find_comment_id(
  in _author hive_accounts.name%TYPE,
  in _permlink hive_permlink_data.permlink%TYPE,
  in _check boolean)
RETURNS INT
LANGUAGE 'plpgsql'
AS
$function$
DECLARE
  __post_id INT = 0;
BEGIN
  IF (_author <> '' OR _permlink <> '') THEN
    SELECT INTO __post_id COALESCE( (
      SELECT hp.id
      FROM hive_posts hp
      JOIN hive_accounts ha ON ha.id = hp.author_id
      JOIN hive_permlink_data hpd ON hpd.id = hp.permlink_id
      WHERE ha.name = _author AND hpd.permlink = _permlink AND hp.counter_deleted = 0
    ), 0 );
    IF _check AND __post_id = 0 THEN
      SELECT INTO __post_id (
        SELECT COUNT(hp.id)
        FROM hive_posts hp
        JOIN hive_accounts ha ON ha.id = hp.author_id
        JOIN hive_permlink_data hpd ON hpd.id = hp.permlink_id
        WHERE ha.name = _author AND hpd.permlink = _permlink
      );
      IF __post_id = 0 THEN
        RAISE EXCEPTION 'Post %/% does not exist', _author, _permlink;
      ELSE
        RAISE EXCEPTION 'Post %/% was deleted % time(s)', _author, _permlink, __post_id;
      END IF;
    END IF;
  END IF;
  RETURN __post_id;
END
$function$
;

DROP FUNCTION IF EXISTS find_account_id(character varying, boolean)
;
CREATE OR REPLACE FUNCTION find_account_id(
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
