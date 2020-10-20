DROP TYPE IF EXISTS database_api_post CASCADE;
CREATE TYPE database_api_post AS (
  id INT,
  community_id INT,
  author VARCHAR(16),
  permlink VARCHAR(255),
  title VARCHAR(512),
  body TEXT,
  category VARCHAR(255),
  depth SMALLINT,
  promoted DECIMAL(10,3),
  payout DECIMAL(10,3),
  last_payout_at TIMESTAMP,
  cashout_time TIMESTAMP,
  is_paidout BOOLEAN,
  children INT,
  votes INT,
  created_at TIMESTAMP,
  updated_at TIMESTAMP,
  rshares NUMERIC,
  json TEXT,
  is_hidden BOOLEAN,
  is_grayed BOOLEAN,
  total_votes BIGINT,
  net_votes BIGINT,
  total_vote_weight NUMERIC,
  parent_author VARCHAR(16),
  parent_permlink_or_category VARCHAR(255),
  curator_payout_value VARCHAR(30),
  root_author VARCHAR(16),
  root_permlink VARCHAR(255),
  max_accepted_payout VARCHAR(30),
  percent_hbd INT,
  allow_replies BOOLEAN,
  allow_votes BOOLEAN,
  allow_curation_rewards BOOLEAN,
  beneficiaries JSON,
  url TEXT,
  root_title VARCHAR(512),
  abs_rshares NUMERIC,
  active TIMESTAMP,
  author_rewards BIGINT
)
;

DROP FUNCTION IF EXISTS list_comments_by_permlink(character varying, character varying, int)
;
CREATE OR REPLACE FUNCTION list_comments_by_permlink(
  in _author hive_accounts.name%TYPE,
  in _permlink hive_permlink_data.permlink%TYPE,
  in _limit INT)
  RETURNS SETOF database_api_post
  LANGUAGE sql
  STABLE
  AS
  $function$
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
        SELECT hp1.id
        FROM
            hive_posts_api_helper hp1
        INNER JOIN hive_posts hp2 ON hp2.id = hp1.id
        WHERE
            hp2.counter_deleted = 0 AND NOT hp2.is_muted AND hp1.id != 0
            AND hp1.author_s_permlink >= _author || '/' || _permlink
        ORDER BY
            hp1.author_s_permlink
        LIMIT
            _limit
    ) ds ON ds.id = hp.id
    ORDER BY
      hp.author, hp.permlink
  $function$
;

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
    __post_id = find_comment_id(_author,_permlink, True);
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
        WHERE
            hp1.counter_deleted = 0
            AND NOT hp1.is_muted
            AND hp1.cashout_time > _cashout_time
            OR hp1.cashout_time = _cashout_time
            AND hp1.id >= __post_id AND hp1.id != 0
        ORDER BY
            hp1.cashout_time ASC,
            hp1.id ASC
        LIMIT
            _limit
    ) ds ON ds.id = hp.id
    ORDER BY
        hp.cashout_time ASC,
        hp.id ASC
    ;
  END
  $function$
  LANGUAGE plpgsql
;

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
    FROM
      hive_posts_view hp
    INNER JOIN
    (
      SELECT
        hp2.id
      FROM
        hive_posts hp2
      WHERE
        hp2.counter_deleted = 0
        AND NOT hp2.is_muted
        AND hp2.root_id = __root_id
        AND hp2.id >= __post_id
      ORDER BY
        hp2.id ASC
      LIMIT _limit
    ) ds on hp.id = ds.id
    ORDER BY
      hp.id
    ;
  END
  $function$
  LANGUAGE plpgsql
;

DROP FUNCTION IF EXISTS list_comments_by_parent(character varying, character varying, character varying, character varying, int)
;
CREATE OR REPLACE FUNCTION list_comments_by_parent(
  in _parent_author hive_accounts.name%TYPE,
  in _parent_permlink hive_permlink_data.permlink%TYPE,
  in _start_post_author hive_accounts.name%TYPE,
  in _start_post_permlink hive_permlink_data.permlink%TYPE,
  in _limit INT)
  RETURNS SETOF database_api_post
AS $function$
DECLARE
  __post_id INT;
  __parent_id INT;
BEGIN
  __parent_id = find_comment_id(_parent_author, _parent_permlink, True);
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
    SELECT hp1.id FROM
      hive_posts hp1
    WHERE
      hp1.counter_deleted = 0
      AND NOT hp1.is_muted
      AND hp1.parent_id = __parent_id
      AND hp1.id >= __post_id
    ORDER BY
      hp1.id ASC
    LIMIT
      _limit
  ) ds ON ds.id = hp.id
  ORDER BY
    hp.id
  ;
END
$function$
LANGUAGE plpgsql
;

DROP FUNCTION IF EXISTS list_comments_by_last_update(character varying, timestamp, character varying, character varying, int)
;
CREATE OR REPLACE FUNCTION list_comments_by_last_update(
  in _parent_author hive_accounts.name%TYPE,
  in _updated_at hive_posts.updated_at%TYPE,
  in _start_post_author hive_accounts.name%TYPE,
  in _start_post_permlink hive_permlink_data.permlink%TYPE,
  in _limit INT)
  RETURNS SETOF database_api_post
  AS
  $function$
  DECLARE
    __post_id INT;
    __parent_author_id INT;
  BEGIN
    __parent_author_id = find_account_id(_parent_author, True);
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
        JOIN
          hive_posts hp2 ON hp1.parent_id = hp2.id
        WHERE
          hp1.counter_deleted = 0
          AND NOT hp1.is_muted
          AND hp2.author_id = __parent_author_id
          AND (
            hp1.updated_at < _updated_at
            OR hp1.updated_at = _updated_at
            AND hp1.id >= __post_id
          )
        ORDER BY
          hp1.updated_at DESC,
          hp1.id ASC
        LIMIT
          _limit
    ) ds ON ds.id = hp.id
    ORDER BY
      hp.updated_at DESC,
      hp.id ASC
    ;
  END
  $function$
  LANGUAGE plpgsql
;

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
    __author_id INT;
    __post_id INT;
  BEGIN
    __author_id = find_account_id(_author, True);
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
      WHERE
        hp1.counter_deleted = 0
        AND NOT hp1.is_muted
        AND hp1.author_id = __author_id
        AND (
          hp1.updated_at < _updated_at
          OR hp1.updated_at = _updated_at
          AND hp1.id >= __post_id
        )
      ORDER BY
        hp1.updated_at DESC,
        hp1.id ASC
      LIMIT
        _limit
    ) ds ON ds.id = hp.id
    ORDER BY
        hp.updated_at DESC,
        hp.id ASC
    ;
  END
  $function$
  LANGUAGE plpgsql
;
