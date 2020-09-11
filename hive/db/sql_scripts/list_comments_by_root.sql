DROP FUNCTION IF EXISTS list_comments_by_root(character varying, character varying, character varying, character varying, int)
;
CREATE OR REPLACE FUNCTION list_comments_by_root(
  in _root_author hive_accounts.name%TYPE,
  in _root_permlink hive_permlink_data.permlink%TYPE,
  in _start_post_author hive_accounts.name%TYPE,
  in _start_post_permlink hive_permlink_data.permlink%TYPE,
  in _limit INT)
  RETURNS SETOF database_api_post
  AS
  $function$
  DECLARE
    __root_id INT;
    __post_id INT;
  BEGIN
    __root_id = find_comment_id(_root_author, _root_permlink, True);
    __post_id = find_comment_id(_start_post_author, _start_post_permlink, True);
    RETURN QUERY
    SELECT
      hp.id, hp.community_id, hp.author, hp.permlink, hp.title, hp.body,
      hp.category, hp.depth, hp.promoted, hp.payout, hp.last_payout_at, hp.cashout_time, hp.is_paidout,
      hp.children, hp.votes, hp.created_at, hp.updated_at, hp.rshares, hp.json,
      hp.is_hidden, hp.is_grayed, hp.total_votes, hp.net_votes, hp.total_vote_weight,
      hp.parent_author, hp.parent_permlink_or_category, hp.curator_payout_value, hp.root_author, hp.root_permlink,
      hp.max_accepted_payout, hp.percent_hbd, hp.allow_replies, hp.allow_votes,
      hp.allow_curation_rewards, hp.beneficiaries, hp.url, hp.root_title, hp.abs_rshares,
      hp.active, hp.author_rewards
    FROM hive_posts_view hp
    INNER JOIN 
    (
    SELECT hp2.id, hp2.root_id FROM hive_posts hp2
    WHERE NOT hp2.is_muted
          AND hp2.root_id > __root_id
          OR hp2.root_id = __root_id AND hp2.id >= __post_id AND hp2.id > 0
    ORDER BY
        hp2.root_id ASC
      ,hp2.id ASC
    LIMIT _limit
    ) ds on hp.id = ds.id
    ;
  END
  $function$
  LANGUAGE plpgsql
;