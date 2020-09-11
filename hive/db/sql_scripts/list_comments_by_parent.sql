DROP FUNCTION IF EXISTS list_comments_by_parent(character varying, character varying, character varying, character varying, int)
;
CREATE OR REPLACE FUNCTION list_comments_by_parent(
  in _parent_author hive_accounts.name%TYPE,
  in _parent_permlink hive_permlink_data.permlink%TYPE,
  in _start_post_author hive_accounts.name%TYPE,
  in _start_post_permlink hive_permlink_data.permlink%TYPE,
  in _limit INT)
  RETURNS SETOF database_api_post 
  LANGUAGE sql
  COST 100
  STABLE
  ROWS 1000
AS $function$
  SELECT
    hp.id, hp.community_id, hp.author, hp.permlink, hp.title, hp.body,
    hp.category, hp.depth, hp.promoted, hp.payout, hp.last_payout_at, hp.cashout_time, hp.is_paidout,
    hp.children, hp.votes, hp.created_at, hp.updated_at, hp.rshares, hp.json,
    hp.is_hidden, hp.is_grayed, hp.total_votes, hp.net_votes, hp.total_vote_weight,
    hp.parent_author, hp.parent_permlink_or_category, hp.curator_payout_value, hp.root_author, hp.root_permlink,
    hp.max_accepted_payout, hp.percent_hbd, hp.allow_replies, hp.allow_votes,
    hp.allow_curation_rewards, hp.beneficiaries, hp.url, hp.root_title, hp.abs_rshares,
    hp.active, hp.author_rewards
  FROM
    hive_posts_view hp
    INNER JOIN
    (
      SELECT h.id FROM
      hive_posts_api_helper h
      WHERE
        h.parent_author > _parent_author OR
        h.parent_author = _parent_author AND ( h.parent_permlink_or_category > _parent_permlink OR
        h.parent_permlink_or_category = _parent_permlink AND h.id >= find_comment_id(_start_post_author, _start_post_permlink, True) )
      ORDER BY
        h.parent_author ASC,
        h.parent_permlink_or_category ASC,
        h.id ASC
      LIMIT
        _limit
    ) ds ON ds.id = hp.id
  WHERE
    NOT hp.is_muted
    ;
$function$
;