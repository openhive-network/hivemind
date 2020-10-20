DROP FUNCTION IF EXISTS get_by_replies_to_account;

CREATE OR REPLACE FUNCTION get_by_replies_to_account(
  in _author VARCHAR,
  in _permlink VARCHAR,
  in _limit INTEGER
)
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER := 0;
  __posts_ids INTEGER[];
BEGIN

  IF _permlink <> '' THEN
    SELECT
          (SELECT name FROM hive_accounts ha WHERE ha.id = parent.author_id), child.id
    INTO
          _author, __post_id
    FROM hive_posts child
    JOIN hive_posts parent ON child.parent_id = parent.id
    WHERE child.author_id = (SELECT ha.id FROM hive_accounts ha WHERE ha.name = _author)
    AND child.permlink_id = (SELECT hpd.id FROM hive_permlink_data hpd WHERE hpd.permlink = _permlink);
  END IF;
 
  __posts_ids = ARRAY
  (
    SELECT hp.id
    FROM hive_posts hp
    JOIN hive_accounts ha ON hp.author_id = ha.id
    WHERE ha.name = _author
    ORDER BY hp.id DESC
    LIMIT 10000
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
    WHERE hp.parent_id = ANY( __posts_ids )
    AND ( ( __post_id = 0 ) OR ( hp.id <= __post_id ) )
    ORDER BY hp.id DESC
    LIMIT _limit;

END
$function$
language plpgsql STABLE;
