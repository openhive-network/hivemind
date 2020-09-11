DROP FUNCTION if exists delete_hive_post(character varying,character varying,character varying)
;
CREATE OR REPLACE FUNCTION delete_hive_post(
  in _author hive_accounts.name%TYPE,
  in _permlink hive_permlink_data.permlink%TYPE)
RETURNS TABLE (id hive_posts.id%TYPE, depth hive_posts.depth%TYPE)
LANGUAGE plpgsql
AS
$function$
BEGIN
  RETURN QUERY UPDATE hive_posts AS hp
    SET counter_deleted =
    (
      SELECT max( hps.counter_deleted ) + 1
      FROM hive_posts hps
      INNER JOIN hive_accounts ha ON hps.author_id = ha.id
      INNER JOIN hive_permlink_data hpd ON hps.permlink_id = hpd.id
      WHERE ha.name = _author AND hpd.permlink = _permlink
    )
  FROM hive_posts hp1
  INNER JOIN hive_accounts ha ON hp1.author_id = ha.id
  INNER JOIN hive_permlink_data hpd ON hp1.permlink_id = hpd.id
  WHERE hp.id = hp1.id AND ha.name = _author AND hpd.permlink = _permlink AND hp1.counter_deleted = 0
  RETURNING hp.id, hp.depth;
END
$function$
;