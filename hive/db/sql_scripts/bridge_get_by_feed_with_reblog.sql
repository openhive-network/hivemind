DROP FUNCTION IF EXISTS hivemind_app.bridge_get_by_feed_with_reblog;

CREATE OR REPLACE FUNCTION hivemind_app.bridge_get_by_feed_with_reblog( IN _account VARCHAR, IN _author VARCHAR, IN _permlink VARCHAR, IN _limit INTEGER, IN _observer VARCHAR)
    RETURNS SETOF hivemind_app.bridge_api_post_reblogs
    LANGUAGE 'plpgsql'
    STABLE 
    ROWS 1000
AS $BODY$
DECLARE
  __post_id INT;
  __cutoff INT;
  __account_id INT;
  __min_date TIMESTAMP;
  __observer_id INT;
BEGIN
  __account_id = hivemind_app.find_account_id( _account, True );
  __observer_id = hivemind_app.find_account_id( _observer, True );
  __post_id = hivemind_app.find_comment_id( _author, _permlink, True );
  IF __post_id <> 0 THEN
    SELECT MIN(hfc.created_at) INTO __min_date
    FROM hivemind_app.hive_feed_cache hfc
    JOIN hivemind_app.hive_follows hf ON hfc.account_id = hf.following
    WHERE hf.state = 1 AND hf.follower = __account_id AND hfc.post_id = __post_id;
  END IF;

  __cutoff = hivemind_app.block_before_head( '1 month' );

  RETURN QUERY 
  WITH feed AS MATERIALIZED -- bridge_get_by_feed_with_reblog
  (
    SELECT 
      hfc.post_id, 
      MIN(hfc.created_at) as min_created, 
      array_agg(ha.name) AS reblogged_by,
      array_agg(blacklist.source) as blacklist_source
    FROM hivemind_app.hive_feed_cache hfc
    JOIN hivemind_app.hive_follows hf ON hfc.account_id = hf.following
    JOIN hivemind_app.hive_accounts ha ON ha.id = hf.following
    LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (__observer_id != 0 AND blacklist.observer_id = __observer_id AND blacklist.blacklisted_id = hfc.account_id)
    WHERE hfc.block_num > __cutoff AND hf.state = 1 AND hf.follower = __account_id
    AND (__observer_id = 0 OR NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = __observer_id AND muted_id = hfc.account_id))
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
      feed.reblogged_by,
      (SELECT array_to_string(feed.blacklist_source, ',', '')),
      hp.muted_reasons
  FROM feed,
  LATERAL hivemind_app.get_post_view_by_id(feed.post_id) hp
  ORDER BY feed.min_created DESC, feed.post_id DESC
  LIMIT _limit;
END
$BODY$
;
