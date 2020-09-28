DROP FUNCTION IF EXISTS get_account_post_replies;
CREATE FUNCTION get_account_post_replies( in _account VARCHAR, in start_author VARCHAR, in start_permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF INTEGER
AS
$function$
DECLARE
  __post_id INT;
  __account_id INT;
BEGIN
  __post_id = find_comment_id( start_author, start_permlink, True );
  __account_id = find_account_id( _account, True );
  RETURN QUERY SELECT
      hpr.id as id
  FROM hive_posts hpr
  JOIN hive_posts hp ON hp.id = hpr.parent_id
  WHERE hp.author_id = __account_id AND hp.counter_deleted = 0 AND hpr.counter_deleted = 0 AND ( __post_id = 0 OR hpr.id < __post_id )
  ORDER BY hpr.id DESC
  LIMIT _limit;
END
$function$
LANGUAGE plpgsql STABLE
