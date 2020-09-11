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
  post_id INT;
BEGIN
  SELECT INTO post_id COALESCE( (SELECT hp.id
  FROM hive_posts hp
  JOIN hive_accounts ha ON ha.id = hp.author_id
  JOIN hive_permlink_data hpd ON hpd.id = hp.permlink_id
  WHERE ha.name = _author AND hpd.permlink = _permlink AND hp.counter_deleted = 0
  ), 0 );
  IF _check AND (_author <> '' OR _permlink <> '') AND post_id = 0 THEN
    RAISE EXCEPTION 'Post %/% does not exist', _author, _permlink;
  END IF;
  RETURN post_id;
END
$function$
;