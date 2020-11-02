DROP FUNCTION IF EXISTS condenser_get_by_feed_with_reblog;

CREATE OR REPLACE FUNCTION condenser_get_by_feed_with_reblog(
  in _account VARCHAR,
  in _author VARCHAR,
  in _permlink VARCHAR,
  in _limit INTEGER
)
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER := 0;
  __cutoff INTEGER;
  __account_id INTEGER := find_account_id( _account, True );
  __min_data TIMESTAMP;
BEGIN

  IF _permlink <> '' THEN
    __post_id = find_comment_id( _author, _permlink, True );
  END IF;

  __cutoff = block_before_head( '1 month' );
  __min_data =
  (
      SELECT MIN(hfc.created_at)
      FROM hive_feed_cache hfc
      JOIN hive_follows hf ON hfc.account_id = hf.following
      WHERE hf.state = 1 AND hf.follower = __account_id AND ( ( __post_id = 0 ) OR ( hfc.post_id = __post_id ) )
  );

  RETURN QUERY SELECT
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
      hp.curator_payout_value
    FROM hive_posts_view hp
    JOIN
    (
      SELECT hfc.post_id
      FROM hive_feed_cache hfc
      JOIN
      (
        SELECT following
        FROM hive_follows
        WHERE state = 1 AND follower = __account_id
      ) T ON hfc.account_id = T.following
      JOIN hive_feed_cache hfc2 ON hfc2.account_id = T.following AND( __post_id = 0 OR hfc.post_id <= __post_id )
      WHERE hfc.block_num > __cutoff
      GROUP BY hfc.post_id
      HAVING ( __post_id = 0 ) OR ( MIN(hfc.created_at) <= __min_data )
      ORDER BY MIN(hfc.created_at) DESC
      LIMIT _limit
    ) T ON hp.id =  T.post_id;
END
$function$
language plpgsql STABLE;
