DROP FUNCTION IF EXISTS list_comments_by_author_last_update(character varying, timestamp, character varying, character varying, int)
;
CREATE OR REPLACE FUNCTION list_comments_by_author_last_update(
  in _author hive_accounts.name%TYPE,
  in _updated_at hive_posts.updated_at%TYPE,
  in _start_post_author hive_accounts.name%TYPE,
  in _start_post_permlink hive_permlink_data.permlink%TYPE,
  in _limit INT)
  RETURNS SETOF database_api_post
  AS
  $function$
  DECLARE
    __post_id INT;
  BEGIN
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
    FROM
        hive_posts_view hp
    INNER JOIN
    (
        SELECT 
          hp1.id
        FROM
          hive_posts hp1
        INNER JOIN hive_accounts ha ON ha.id = hp1.author_id
        WHERE
            NOT hp1.is_muted AND
            -- fat node used wrong index (by_last_update) so the results are vastly different
            ha.name > _author OR
            ha.name = _author AND ( hp1.updated_at < _updated_at OR
            hp1.updated_at = _updated_at AND hp1.id >= __post_id )
        ORDER BY
            ha.name ASC,
            hp1.updated_at DESC,
            hp1.id ASC
        -- with limit inside it returns _limit - 1 records in 300ms, outside it return _limit records but in 1000ms
        -- adding + 1 returns _limit records in 300ms
        LIMIT
            _limit + 1
    ) ds ON ds.id = hp.id
    ;
  END
  $function$
  LANGUAGE plpgsql
;