DROP FUNCTION IF EXISTS condenser_get_top_trending_tags_summary;
CREATE FUNCTION condenser_get_top_trending_tags_summary( in _limit INT )
RETURNS SETOF VARCHAR
AS
$function$
BEGIN
  RETURN QUERY SELECT
      hcd.category
  FROM
      hive_category_data hcd
      JOIN hive_posts hp ON hp.category_id = hcd.id
  WHERE hp.counter_deleted = 0 AND NOT hp.is_paidout
  GROUP BY hcd.category
  ORDER BY SUM(hp.payout + hp.pending_payout) DESC
  LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS condenser_get_trending_tags;
CREATE FUNCTION condenser_get_trending_tags( in _category VARCHAR, in _limit INT )
RETURNS TABLE( category VARCHAR, total_posts BIGINT, top_posts BIGINT, total_payouts hive_posts.payout%TYPE )
AS
$function$
DECLARE
  __category_id INT;
  __payout_limit hive_posts.payout%TYPE;
BEGIN
  __category_id = find_category_id( _category, True );
  IF __category_id <> 0 THEN
      SELECT SUM(hp.payout + hp.pending_payout) INTO __payout_limit
      FROM hive_posts hp
      WHERE hp.category_id = __category_id AND hp.counter_deleted = 0 AND NOT hp.is_paidout;
  END IF;
  RETURN QUERY SELECT
      hcd.category,
      COUNT(*) AS total_posts,
      SUM(CASE WHEN hp.depth = 0 THEN 1 ELSE 0 END) AS top_posts,
      SUM(hp.payout + hp.pending_payout) AS total_payouts
  FROM
      hive_posts hp
      JOIN hive_category_data hcd ON hcd.id = hp.category_id
  WHERE NOT hp.is_paidout AND counter_deleted = 0
  GROUP BY hcd.category
  HAVING __category_id = 0 OR SUM(hp.payout + hp.pending_payout) < __payout_limit OR ( SUM(hp.payout + hp.pending_payout) = __payout_limit AND hcd.category > _category )
  ORDER BY SUM(hp.payout + hp.pending_payout) DESC, hcd.category ASC
  LIMIT _limit;
END
$function$
language plpgsql STABLE;
