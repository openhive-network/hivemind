DROP FUNCTION IF EXISTS get_pids_by_blog_without_reblog;

CREATE OR REPLACE FUNCTION get_pids_by_blog_without_reblog(
  in _account VARCHAR,
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
  _id INTEGER := ( SELECT ha.id FROM hive_accounts ha WHERE ha.name = _account );
BEGIN

	RETURN QUERY
		SELECT hp.id
		FROM hive_posts hp
		WHERE author_id = _id
		AND ( ( _is_start_id = false ) OR ( ( _is_start_id = true ) AND ( hp.id <= _start_id ) ) )
		AND depth = 0
		AND counter_deleted = 0
		ORDER BY id DESC
		LIMIT _limit;

END
$function$
LANGUAGE plpgsql
;
