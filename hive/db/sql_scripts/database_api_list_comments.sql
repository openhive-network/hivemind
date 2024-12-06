DROP TYPE IF EXISTS hivemind_app.database_api_post CASCADE;
CREATE TYPE hivemind_app.database_api_post AS (
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
  author_rewards BIGINT,
  muted_reasons INTEGER
);

DROP FUNCTION IF EXISTS hivemind_app.list_comments_by_permlink(character varying, character varying, int);
CREATE OR REPLACE FUNCTION hivemind_app.list_comments_by_permlink(
  in _author hivemind_app.hive_accounts.name%TYPE,
  in _permlink hivemind_app.hive_permlink_data.permlink%TYPE,
  in _limit INT)
  RETURNS SETOF hivemind_app.database_api_post
AS
$function$
BEGIN
  RETURN QUERY
  WITH comments AS MATERIALIZED -- list_comments_by_permlink
  (
    SELECT
      hph.id,
      hph.author_s_permlink
    FROM hivemind_app.hive_posts_api_helper hph
    JOIN hivemind_app.live_posts_comments_view hp ON hp.id = hph.id
    WHERE hph.author_s_permlink >= _author || '/' || _permlink
      AND NOT hp.is_muted -- all the mute checks in this file look insufficient, but maybe no one uses these API calls?
      AND hph.id != 0 -- what does this do?
    ORDER BY hph.author_s_permlink
    LIMIT _limit
  )
  SELECT
        hp.id, hp.community_id, hp.author, hp.permlink, hp.title, hp.body,
        hp.category, hp.depth, hp.promoted, hp.payout, hp.last_payout_at, hp.cashout_time, hp.is_paidout,
        hp.children, hp.votes, hp.created_at, hp.updated_at, hp.rshares, hp.json,
        hp.is_hidden, hp.is_grayed, hp.total_votes, hp.net_votes, hp.total_vote_weight,
        hp.parent_author, hp.parent_permlink_or_category, hp.curator_payout_value, hp.root_author, hp.root_permlink,
        hp.max_accepted_payout, hp.percent_hbd, hp.allow_replies, hp.allow_votes,
        hp.allow_curation_rewards, hp.beneficiaries, hp.url, hp.root_title, hp.abs_rshares,
        hp.active, hp.author_rewards, hp.muted_reasons
  FROM comments,
  LATERAL hivemind_app.get_post_view_by_id(comments.id) hp
  ORDER BY hp.author, hp.permlink
  LIMIT _limit;
END;
$function$
LANGUAGE plpgsql STABLE;

DROP FUNCTION IF EXISTS hivemind_app.list_comments_by_cashout_time(timestamp, character varying, character varying, int);
CREATE OR REPLACE FUNCTION hivemind_app.list_comments_by_cashout_time(
  in _cashout_time timestamp,
  in _author hivemind_app.hive_accounts.name%TYPE,
  in _permlink hivemind_app.hive_permlink_data.permlink%TYPE,
  in _limit INT)
  RETURNS SETOF hivemind_app.database_api_post
AS
$function$
DECLARE
  __post_id INT;
BEGIN
  __post_id = hivemind_app.find_comment_id(_author,_permlink, True);
  RETURN QUERY
  WITH comments AS MATERIALIZED -- list_comments_by_cashout_time
  (
    SELECT
      hp1.id,
      hp1.cashout_time
    FROM hivemind_app.live_posts_comments_view hp1
    WHERE NOT hp1.is_muted
      AND hp1.cashout_time > _cashout_time
       OR hp1.cashout_time = _cashout_time
      AND hp1.id >= __post_id AND hp1.id != 0
    ORDER BY
      hp1.cashout_time ASC,
      hp1.id ASC
    LIMIT _limit
  )
  SELECT
        hp.id, hp.community_id, hp.author, hp.permlink, hp.title, hp.body,
        hp.category, hp.depth, hp.promoted, hp.payout, hp.last_payout_at, hp.cashout_time, hp.is_paidout,
        hp.children, hp.votes, hp.created_at, hp.updated_at, hp.rshares, hp.json,
        hp.is_hidden, hp.is_grayed, hp.total_votes, hp.net_votes, hp.total_vote_weight,
        hp.parent_author, hp.parent_permlink_or_category, hp.curator_payout_value, hp.root_author, hp.root_permlink,
        hp.max_accepted_payout, hp.percent_hbd, hp.allow_replies, hp.allow_votes,
        hp.allow_curation_rewards, hp.beneficiaries, hp.url, hp.root_title, hp.abs_rshares,
        hp.active, hp.author_rewards, hp.muted_reasons
  FROM comments,
  LATERAL hivemind_app.get_post_view_by_id(comments.id) hp
  ORDER BY comments.cashout_time ASC, comments.id ASC
  LIMIT _limit
  ;
END
$function$
LANGUAGE plpgsql STABLE;

DROP FUNCTION IF EXISTS hivemind_app.list_comments_by_root(character varying, character varying, character varying, character varying, int);
CREATE OR REPLACE FUNCTION hivemind_app.list_comments_by_root(
  in _root_author hivemind_app.hive_accounts.name%TYPE,
  in _root_permlink hivemind_app.hive_permlink_data.permlink%TYPE,
  in _start_post_author hivemind_app.hive_accounts.name%TYPE,
  in _start_post_permlink hivemind_app.hive_permlink_data.permlink%TYPE,
  in _limit INT)
  RETURNS SETOF hivemind_app.database_api_post
AS
$function$
DECLARE
  __root_id INT;
  __post_id INT;
BEGIN
  __root_id = hivemind_app.find_comment_id(_root_author, _root_permlink, True);
  __post_id = hivemind_app.find_comment_id(_start_post_author, _start_post_permlink, True);
  RETURN QUERY
  WITH comments AS MATERIALIZED -- list_comments_by_root
  (
    SELECT hp.id
    FROM hivemind_app.live_posts_comments_view hp
    WHERE hp.root_id = __root_id
      AND NOT hp.is_muted
      AND (__post_id = 0 OR hp.id >= __post_id)
    ORDER BY hp.id ASC
    LIMIT _limit
  )
  SELECT
    hp.id, hp.community_id, hp.author, hp.permlink, hp.title, hp.body,
    hp.category, hp.depth, hp.promoted, hp.payout, hp.last_payout_at, hp.cashout_time, hp.is_paidout,
    hp.children, hp.votes, hp.created_at, hp.updated_at, hp.rshares, hp.json,
    hp.is_hidden, hp.is_grayed, hp.total_votes, hp.net_votes, hp.total_vote_weight,
    hp.parent_author, hp.parent_permlink_or_category, hp.curator_payout_value, hp.root_author, hp.root_permlink,
    hp.max_accepted_payout, hp.percent_hbd, hp.allow_replies, hp.allow_votes,
    hp.allow_curation_rewards, hp.beneficiaries, hp.url, hp.root_title, hp.abs_rshares,
    hp.active, hp.author_rewards, hp.muted_reasons
  FROM comments,
  LATERAL hivemind_app.get_post_view_by_id(comments.id) hp
  ORDER BY comments.id
  LIMIT _limit;
END
$function$
LANGUAGE plpgsql STABLE;

DROP FUNCTION IF EXISTS hivemind_app.list_comments_by_parent(character varying, character varying, character varying, character varying, int)
;
CREATE OR REPLACE FUNCTION hivemind_app.list_comments_by_parent(
  in _parent_author hivemind_app.hive_accounts.name%TYPE,
  in _parent_permlink hivemind_app.hive_permlink_data.permlink%TYPE,
  in _start_post_author hivemind_app.hive_accounts.name%TYPE,
  in _start_post_permlink hivemind_app.hive_permlink_data.permlink%TYPE,
  in _limit INT)
  RETURNS SETOF hivemind_app.database_api_post
AS $function$
DECLARE
  __post_id INT;
  __parent_id INT;
BEGIN
  __parent_id = hivemind_app.find_comment_id(_parent_author, _parent_permlink, True);
  __post_id = hivemind_app.find_comment_id(_start_post_author, _start_post_permlink, True);
  RETURN QUERY
  WITH comments AS MATERIALIZED -- list_comments_by_parent
  (
    SELECT hp.id
    FROM hivemind_app.live_posts_comments_view hp
    WHERE hp.parent_id = __parent_id
      AND NOT hp.is_muted
--    AND (__post_id = 0 OR hp.id > __post_id) --DLN I think correct version should look like this to avoid dups in paging, but we should get rid of all list_comments instead probably, so not going to fix it nwo in all the places
      AND (__post_id = 0 OR hp.id >= __post_id)
    ORDER BY hp.id ASC
    LIMIT _limit
  )
  SELECT
    hp.id, hp.community_id, hp.author, hp.permlink, hp.title, hp.body,
    hp.category, hp.depth, hp.promoted, hp.payout, hp.last_payout_at, hp.cashout_time, hp.is_paidout,
    hp.children, hp.votes, hp.created_at, hp.updated_at, hp.rshares, hp.json,
    hp.is_hidden, hp.is_grayed, hp.total_votes, hp.net_votes, hp.total_vote_weight,
    hp.parent_author, hp.parent_permlink_or_category, hp.curator_payout_value, hp.root_author, hp.root_permlink,
    hp.max_accepted_payout, hp.percent_hbd, hp.allow_replies, hp.allow_votes,
    hp.allow_curation_rewards, hp.beneficiaries, hp.url, hp.root_title, hp.abs_rshares,
    hp.active, hp.author_rewards, hp.muted_reasons
  FROM comments,
  LATERAL hivemind_app.get_post_view_by_id(comments.id) hp
  ORDER BY comments.id
  LIMIT _limit;
END
$function$
LANGUAGE plpgsql STABLE;

DROP FUNCTION IF EXISTS hivemind_app.list_comments_by_last_update(character varying, timestamp, character varying, character varying, int)
;
CREATE OR REPLACE FUNCTION hivemind_app.list_comments_by_last_update(
  in _parent_author hivemind_app.hive_accounts.name%TYPE,
  in _updated_at hivemind_app.hive_posts.updated_at%TYPE,
  in _start_post_author hivemind_app.hive_accounts.name%TYPE,
  in _start_post_permlink hivemind_app.hive_permlink_data.permlink%TYPE,
  in _limit INT)
  RETURNS SETOF hivemind_app.database_api_post
AS
$function$
DECLARE
   __post_id INT;
   __parent_author_id INT;
BEGIN
  __parent_author_id = hivemind_app.find_account_id(_parent_author, True);
  __post_id = hivemind_app.find_comment_id(_start_post_author, _start_post_permlink, True);
  RETURN QUERY
  WITH comments AS MATERIALIZED -- list_comments_by_last_update
  (
    SELECT
      hp1.id,
      hp1.updated_at
    FROM hivemind_app.live_posts_comments_view hp1
    JOIN hivemind_app.hive_posts hp2 ON hp1.parent_id = hp2.id
    WHERE hp2.author_id = __parent_author_id
        AND NOT hp1.is_muted
        AND (
            hp1.updated_at < _updated_at
            OR hp1.updated_at = _updated_at AND hp1.id >= __post_id AND hp1.id != 0
            )
    ORDER BY hp1.updated_at DESC, hp1.id ASC
    LIMIT _limit
  )
  SELECT
      hp.id, hp.community_id, hp.author, hp.permlink, hp.title, hp.body,
      hp.category, hp.depth, hp.promoted, hp.payout, hp.last_payout_at, hp.cashout_time, hp.is_paidout,
      hp.children, hp.votes, hp.created_at, hp.updated_at, hp.rshares, hp.json,
      hp.is_hidden, hp.is_grayed, hp.total_votes, hp.net_votes, hp.total_vote_weight,
      hp.parent_author, hp.parent_permlink_or_category, hp.curator_payout_value, hp.root_author, hp.root_permlink,
      hp.max_accepted_payout, hp.percent_hbd, hp.allow_replies, hp.allow_votes,
      hp.allow_curation_rewards, hp.beneficiaries, hp.url, hp.root_title, hp.abs_rshares,
      hp.active, hp.author_rewards, hp.muted_reasons
  FROM comments,
  LATERAL hivemind_app.get_post_view_by_id(comments.id) hp
  ORDER BY comments.updated_at DESC, comments.id ASC
  LIMIT _limit;
END
$function$
LANGUAGE plpgsql STABLE;

DROP FUNCTION IF EXISTS hivemind_app.list_comments_by_author_last_update(character varying, timestamp, character varying, character varying, int)
;
CREATE OR REPLACE FUNCTION hivemind_app.list_comments_by_author_last_update(
  in _author hivemind_app.hive_accounts.name%TYPE,
  in _updated_at hivemind_app.hive_posts.updated_at%TYPE,
  in _start_post_author hivemind_app.hive_accounts.name%TYPE,
  in _start_post_permlink hivemind_app.hive_permlink_data.permlink%TYPE,
  in _limit INT)
  RETURNS SETOF hivemind_app.database_api_post
AS
$function$
DECLARE
  __author_id INT;
  __post_id INT;
BEGIN
  __author_id = hivemind_app.find_account_id(_author, True);
  __post_id = hivemind_app.find_comment_id(_start_post_author, _start_post_permlink, True);
  RETURN QUERY
  WITH comments AS MATERIALIZED -- list_comments_by_author_last_update
  (
    SELECT
      hp1.id,
      hp1.updated_at
    FROM hivemind_app.live_posts_comments_view hp1
    WHERE hp1.author_id = __author_id
      AND NOT hp1.is_muted
      AND (
          hp1.updated_at < _updated_at
          OR hp1.updated_at = _updated_at
          AND hp1.id >= __post_id AND hp1.id != 0
          )
    ORDER BY hp1.updated_at DESC, hp1.id ASC
    LIMIT _limit
  )
  SELECT
      hp.id, hp.community_id, hp.author, hp.permlink, hp.title, hp.body,
      hp.category, hp.depth, hp.promoted, hp.payout, hp.last_payout_at, hp.cashout_time, hp.is_paidout,
      hp.children, hp.votes, hp.created_at, hp.updated_at, hp.rshares, hp.json,
      hp.is_hidden, hp.is_grayed, hp.total_votes, hp.net_votes, hp.total_vote_weight,
      hp.parent_author, hp.parent_permlink_or_category, hp.curator_payout_value, hp.root_author, hp.root_permlink,
      hp.max_accepted_payout, hp.percent_hbd, hp.allow_replies, hp.allow_votes,
      hp.allow_curation_rewards, hp.beneficiaries, hp.url, hp.root_title, hp.abs_rshares,
      hp.active, hp.author_rewards, hp.muted_reasons
  FROM comments,
  LATERAL hivemind_app.get_post_view_by_id(comments.id) hp
  ORDER BY comments.updated_at DESC, comments.id ASC
  LIMIT _limit;
END
$function$
LANGUAGE plpgsql STABLE;
