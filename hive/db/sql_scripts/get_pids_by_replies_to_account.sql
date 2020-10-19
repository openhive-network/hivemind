DROP FUNCTION IF EXISTS get_pids_by_replies_to_account;

CREATE OR REPLACE FUNCTION get_pids_by_replies_to_account(
  in _permlink VARCHAR,
  in _start_author VARCHAR,
  in _start_id INTEGER,
  in _is_start_id BOOLEAN,
  in _limit INTEGER
)
RETURNS TABLE
(
  id hive_posts.id%TYPE
)
AS
$function$
DECLARE
  _id INTEGER;
  _posts_ids INTEGER[];
BEGIN

  IF _permlink <> '' THEN
    SELECT
          (SELECT name FROM hive_accounts WHERE id = parent.author_id), child.id
    INTO
          _start_author, _start_id
    FROM hive_posts child
    JOIN hive_posts parent ON child.parent_id = parent.id
    WHERE child.author_id = (SELECT id FROM hive_accounts WHERE name = _start_author)
    AND child.permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = _permlink);
  END IF;

  _id = ( SELECT ha.id FROM hive_accounts ha WHERE ha.name = _start_author );

  _posts_ids = ARRAY
  (
    SELECT hp.id
    FROM hive_posts hp
    WHERE hp.author_id = _id AND hp.counter_deleted = 0
    ORDER BY hp.id DESC
    LIMIT 10000
  );

  RETURN QUERY
      SELECT hp.id FROM hive_posts hp
      WHERE hp.parent_id = ANY( _posts_ids )
      AND ( ( _is_start_id = false ) OR ( ( _is_start_id = true ) AND ( hp.id <= _start_id ) ) )
      AND hp.counter_deleted = 0
      ORDER BY hp.id DESC
      LIMIT _limit;
END
$function$
LANGUAGE plpgsql
;
