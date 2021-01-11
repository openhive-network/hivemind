DROP FUNCTION IF EXISTS bridge_get_by_feed_with_reblog;

CREATE OR REPLACE FUNCTION bridge_get_by_feed_with_reblog( IN _account VARCHAR, IN _author VARCHAR, IN _permlink VARCHAR, IN _limit INTEGER)
    RETURNS SETOF bridge_api_post_reblogs
    LANGUAGE 'plpgsql' STABLE PARALLEL SAFE
    ROWS 1000
AS $BODY$
DECLARE
  __post_id INT;
  __cutoff INT;
  __account_id INT;
  __min_date TIMESTAMP;
BEGIN
  __account_id = find_account_id( _account, True );
  __post_id = find_comment_id( _author, _permlink, True );
  IF __post_id <> 0 THEN
    SELECT MIN(hfc.created_at) INTO __min_date
    FROM hive_feed_cache hfc
    JOIN hive_follows hf ON hfc.account_id = hf.following
    WHERE hf.state = 1 AND hf.follower = __account_id AND hfc.post_id = __post_id;
  END IF;

  __cutoff = block_before_head( '1 month' );

  RETURN QUERY 
  WITH feed AS -- bridge_get_by_feed_with_reblog
  (
    SELECT 
      hfc.post_id, 
      MIN(hfc.created_at) as min_created, 
      array_agg(ha.name) AS reblogged_by
    FROM hive_feed_cache hfc
    JOIN hive_follows hf ON hfc.account_id = hf.following
    JOIN hive_accounts ha ON ha.id = hf.following
    WHERE hfc.block_num > __cutoff AND hf.state = 1 AND hf.follower = __account_id
    GROUP BY hfc.post_id
    HAVING __post_id = 0 OR MIN(hfc.created_at) < __min_date OR ( MIN(hfc.created_at) = __min_date AND hfc.post_id < __post_id )
    ORDER BY min_created DESC, hfc.post_id DESC
    LIMIT _limit
  )
  SELECT
      hp.id,
      hp.author,
      hp.parent_author,
      hp.author_rep,
      hp.root_title,
      hp.beneficiaries,
      hp.max_accepted_payout,
      hp.percent_hbd,
      hp.url,
      hp.permlink,
      hp.parent_permlink_or_category,
      hp.title,
      hp.body,
      hp.category,
      hp.depth,
      hp.promoted,
      hp.payout,
      hp.pending_payout,
      hp.payout_at,
      hp.is_paidout,
      hp.children,
      hp.votes,
      hp.created_at,
      hp.updated_at,
      hp.rshares,
      hp.abs_rshares,
      hp.json,
      hp.is_hidden,
      hp.is_grayed,
      hp.total_votes,
      hp.sc_trend,
      hp.role_title,
      hp.community_title,
      hp.role_id,
      hp.is_pinned,
      hp.curator_payout_value,
      hp.is_muted,
      feed.reblogged_by
  FROM feed,
  LATERAL get_post_view_by_id(feed.post_id) hp
  ORDER BY feed.min_created DESC, feed.post_id DESC
  LIMIT _limit;
END
$BODY$
;
