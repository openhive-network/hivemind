DROP FUNCTION IF EXISTS bridge_get_account_posts_by_replies;

CREATE FUNCTION bridge_get_account_posts_by_replies( in _account VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT, in _bridge_api BOOLEAN )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __account_id INT;
  __post_id INT;
BEGIN
  IF NOT _bridge_api AND _permlink <> '' THEN
      -- find blogger account using parent author of page defining post
      __post_id = find_comment_id( _author, _permlink, True );
      SELECT pp.author_id INTO __account_id
      FROM hive_posts hp
      JOIN hive_posts pp ON hp.parent_id = pp.id
      WHERE hp.id = __post_id;
      IF __account_id = 0 THEN __account_id = NULL; END IF;
  ELSE
      __account_id = find_account_id( _account, True );
      __post_id = find_comment_id( _author, _permlink, True );
  END IF;
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
      hp.curator_payout_value,
      hp.is_muted,
      NULL
  FROM
  (
      SELECT
          hpr.id as id
      FROM
          hive_posts hpr
          JOIN hive_posts hp1 ON hp1.id = hpr.parent_id
      WHERE hp1.author_id = __account_id AND hpr.counter_deleted = 0 AND ( __post_id = 0 OR hpr.id < __post_id )
      ORDER BY hpr.id + 0 DESC
      LIMIT _limit
  ) as replies
  JOIN hive_posts_view hp ON hp.id = replies.id
  ORDER BY replies.id DESC
  LIMIT _limit;
END
$function$
language plpgsql STABLE;
