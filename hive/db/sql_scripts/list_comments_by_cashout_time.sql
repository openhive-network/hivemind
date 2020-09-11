DROP FUNCTION IF EXISTS list_comments_by_cashout_time(timestamp, character varying, character varying, int)
;
CREATE OR REPLACE FUNCTION list_comments_by_cashout_time(
  in _cashout_time timestamp,
  in _author hive_accounts.name%TYPE,
  in _permlink hive_permlink_data.permlink%TYPE,
  in _limit INT)
  RETURNS SETOF database_api_post
  AS
  $function$
  DECLARE
    __post_id INT;
  BEGIN
    __post_id = find_comment_id(_author,_permlink, False);
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
    WHERE
        NOT hp.is_muted AND
        hp.cashout_time > _cashout_time OR
        hp.cashout_time = _cashout_time AND hp.id >= __post_id
    ORDER BY
        hp.cashout_time ASC,
        hp.id ASC
    LIMIT
        _limit
    ;
  END
  $function$
  LANGUAGE plpgsql
;