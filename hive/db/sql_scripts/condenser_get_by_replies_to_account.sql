DROP FUNCTION IF EXISTS condenser_get_by_replies_to_account;

CREATE OR REPLACE FUNCTION condenser_get_by_replies_to_account(
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
    SELECT
        ha_pp.name, hp.id
    INTO
        _author, __post_id
    FROM hive_posts hp
    JOIN hive_posts pp ON hp.parent_id = pp.id
    JOIN hive_accounts ha_pp ON ha_pp.id = pp.author_id
    JOIN hive_permlink_data hpd_pp ON hpd_pp.id = pp.permlink_id
    JOIN hive_accounts ha ON hp.author_id = ha.id
    WHERE 
      hpd_pp.permlink = _permlink AND ha.name =  _author;
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
      hp.is_muted
    FROM hive_posts_view hp
    JOIN
    (
	    SELECT hp.id
	    FROM hive_posts_view hp
	    WHERE hp.author = _author
	    ORDER BY hp.id DESC
	    LIMIT _limit
    ) T ON hp.parent_id = T.id
    WHERE ( ( __post_id = 0 ) OR ( hp.id <= __post_id ) )
    ORDER BY hp.id DESC
    LIMIT _limit;

END
$function$
language plpgsql STABLE;
