DROP FUNCTION IF EXISTS get_by_account_comments;

CREATE OR REPLACE FUNCTION get_by_account_comments(
  in _author VARCHAR,
  in _permlink VARCHAR,
  in _limit INTEGER
)
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER := 0;
BEGIN

  IF _permlink <> '' THEN
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
      hp.curator_payout_value
    FROM hive_posts_view hp
    INNER JOIN hive_accounts ha ON hp.author_id = ha.id AND ha.name = _author
    WHERE ( ( __post_id = 0 ) OR ( hp.id <= __post_id ) ) AND hp.depth > 0
    ORDER BY hp.id DESC, hp.depth
    LIMIT _limit;
END
$function$
language plpgsql STABLE;
