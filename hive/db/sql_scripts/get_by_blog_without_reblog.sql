DROP FUNCTION IF EXISTS get_pids_by_blog_without_reblog;

CREATE OR REPLACE FUNCTION get_pids_by_blog_without_reblog(
  in _author VARCHAR,
  in _permlink VARCHAR,
  in _limit INTEGER
)
RETURNS TABLE
(
  id hive_posts.id%TYPE
)
AS
$function$
DECLARE
  __post_id INTEGER := 0;
  __id INTEGER := ( SELECT ha.id FROM hive_accounts ha WHERE ha.name = _author );
BEGIN

  IF _permlink <> '' THEN
    __post_id = find_comment_id( _author, _permlink, True );
  END IF;

	RETURN QUERY
		SELECT hp.id
		FROM hive_posts hp
		WHERE author_id = __id
		AND ( ( __post_id = 0 ) OR ( hp.id <= __post_id ) )
		AND depth = 0
		AND counter_deleted = 0
		ORDER BY id DESC
		LIMIT _limit;

END
$function$
LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS get_by_blog_without_reblog;

CREATE OR REPLACE FUNCTION get_by_blog_without_reblog(
  in _author VARCHAR,
  in _permlink VARCHAR,
  in _limit INTEGER
)
RETURNS SETOF bridge_api_post
AS
$function$
BEGIN

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
    INNER JOIN get_pids_by_blog_without_reblog( _author, _permlink, _limit ) as fun
    ON hp.id = fun.id;
END
$function$
language plpgsql STABLE;
