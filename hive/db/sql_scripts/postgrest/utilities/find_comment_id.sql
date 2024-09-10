DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.find_comment_id;
CREATE FUNCTION hivemind_postgrest_utilities.find_comment_id(
  in _author hivemind_app.hive_accounts.name%TYPE,
  in _permlink hivemind_app.hive_permlink_data.permlink%TYPE,
  in _check boolean)
RETURNS INT
LANGUAGE 'plpgsql'
STABLE
AS
$function$
DECLARE
  _post_id INT = 0;
BEGIN
  IF (_author <> '' OR _permlink <> '') THEN
    SELECT INTO _post_id COALESCE( (
      SELECT hp.id
      FROM hivemind_app.hive_posts hp
      JOIN hivemind_app.hive_accounts ha ON ha.id = hp.author_id
      JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id
      WHERE ha.name = _author AND hpd.permlink = _permlink AND hp.counter_deleted = 0
    ), 0 );
    IF _check AND _post_id = 0 THEN
      SELECT INTO _post_id (
        SELECT COUNT(hp.id)
        FROM hivemind_app.hive_posts hp
        JOIN hivemind_app.hive_accounts ha ON ha.id = hp.author_id
        JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id
        WHERE ha.name = _author AND hpd.permlink = _permlink
      );
      IF _post_id = 0 THEN
        RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_non_existing_post_exception(_author, _permlink);
      ELSE
        RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_post_deleted_exception(_author, _permlink, _post_id);
      END IF;
    END IF;
  END IF;
  RETURN _post_id;
END
$function$
;