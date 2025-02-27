DROP VIEW IF EXISTS hivemind_app.hive_accounts_rank_view CASCADE;

CREATE OR REPLACE VIEW hivemind_app.hive_accounts_rank_view
 AS
SELECT ha.id,
	  case
      WHEN ds.account_rank < 200 THEN 70
      WHEN ds.account_rank < 1000 THEN 60
      WHEN ds.account_rank < 6500 THEN 50
      WHEN ds.account_rank < 25000 THEN 40
      WHEN ds.account_rank < 100000 THEN 30
      ELSE 20
	  end AS score
FROM hivemind_app.hive_accounts ha
LEFT JOIN
(
  WITH base_rank_data AS
  (
    SELECT ha.id, COALESCE(ha3.reputation,0) as reputation
    FROM hivemind_app.hive_accounts ha
    LEFT JOIN account_reputations ha3 ON ha.haf_id = ha3.account_id
  )
  SELECT brd.id, rank() OVER (ORDER BY brd.reputation DESC) AS account_rank
  FROM base_rank_data brd
  ORDER BY brd.reputation DESC
	LIMIT 150000
  -- Conditions above (related to rank.position) eliminates all records having rank > 100k. So with inclding some
  -- additional space for redundant accounts (having same reputation) lets assume we're limiting it to 150k
  -- As another reason, it can be pointed that only 2% of account has the same reputations, it means only 2000
  -- in 100000, but we get 150000 as 50% would repeat

) ds on ds.id = ha.id
; 

DROP FUNCTION IF EXISTS hivemind_app.calculate_notify_vote_score(_payout hivemind_app.hive_posts.payout%TYPE, _abs_rshares hivemind_app.hive_posts.abs_rshares%TYPE, _rshares hivemind_app.hive_votes.rshares%TYPE) CASCADE
;
CREATE OR REPLACE FUNCTION hivemind_app.calculate_notify_vote_score(_payout hivemind_app.hive_posts.payout%TYPE, _abs_rshares hivemind_app.hive_posts.abs_rshares%TYPE, _rshares hivemind_app.hive_votes.rshares%TYPE)
RETURNS INT
LANGUAGE 'sql'
IMMUTABLE
AS $BODY$
    SELECT CASE
        WHEN ((( _payout )/_abs_rshares) * 1000 * _rshares < 20 ) THEN -1
            ELSE LEAST(100, (LENGTH(CAST( CAST( ( (( _payout )/_abs_rshares) * 1000 * _rshares ) as BIGINT) as text)) - 1) * 25)
    END;
$BODY$;

DROP FUNCTION IF EXISTS hivemind_app.notification_id CASCADE;
CREATE OR REPLACE FUNCTION hivemind_app.notification_id(in _block_number INTEGER, in _notifyType INTEGER, in _id INTEGER)
RETURNS BIGINT
AS
$function$
BEGIN
RETURN CAST( _block_number as BIGINT ) << 36
       | ( _notifyType << 28 )
       | ( _id & CAST( x'0FFFFFFF' as BIGINT) );
END
$function$
LANGUAGE plpgsql IMMUTABLE
;

DROP FUNCTION IF EXISTS hivemind_app.calculate_value_of_vote_on_post CASCADE;
CREATE OR REPLACE FUNCTION hivemind_app.calculate_value_of_vote_on_post(
    _post_payout hivemind_app.hive_posts.payout%TYPE
  , _post_rshares hivemind_app.hive_posts.vote_rshares%TYPE
  , _vote_rshares hivemind_app.hive_votes.rshares%TYPE)
RETURNS FLOAT
LANGUAGE 'sql'
IMMUTABLE
AS $BODY$
    SELECT CASE _post_rshares != 0
              WHEN TRUE THEN CAST( ( _post_payout/_post_rshares ) * _vote_rshares as FLOAT)
           ELSE
              CAST(0 AS FLOAT)
           END
$BODY$;


-- View: hivemind_app.hive_raw_notifications_as_view

-- hive_posts, follows, hive_reblogs, hive_subscriptions, hive_mentions (these are scored by the src account's rank)
DROP VIEW IF EXISTS hivemind_app.hive_raw_notifications_as_view CASCADE;
CREATE OR REPLACE VIEW hivemind_app.hive_raw_notifications_as_view
 AS
 SELECT notifs.block_num,
    notifs.post_id,
    notifs.type_id,
    notifs.created_at,
    notifs.src,
    notifs.dst,
    notifs.dst_post_id,
    notifs.community,
    notifs.community_title,
    notifs.payload,
    harv.score
   FROM (
 SELECT f.block_num,
    0 AS post_id,
    15 AS type_id,
    (select hb.created_at from hivemind_app.blocks_view hb where hb.num = (f.block_num - 1)) as created_at, -- use time of previous block to match head_block_time behavior at given block
    f.follower AS src,
    f.following AS dst,
    0 as dst_post_id,
    ''::character varying(16) AS community,
    ''::character varying AS community_title,
    ''::character varying AS payload
   FROM hivemind_app.follows f

UNION ALL
 SELECT hr.block_num,
    hp.id AS post_id,
    14 AS type_id,
    hr.created_at,
    hr.blogger_id AS src,
    hp.author_id AS dst,
    hr.post_id as dst_post_id,
    ''::character varying(16) AS community,
    ''::character varying AS community_title,
    ''::character varying AS payload
   FROM hivemind_app.hive_reblogs hr -- reblogs
   JOIN hivemind_app.hive_posts hp ON hr.post_id = hp.id
UNION ALL
 SELECT hs.block_num,
    0 AS post_id,
    11 AS type_id,
    hs.created_at,
    hs.account_id AS src,
    hs.community_id AS dst,
    0 as dst_post_id,
    hc.name AS community,
    hc.title AS community_title,
    ''::character varying AS payload
   FROM hivemind_app.hive_subscriptions hs -- subscriptions
   JOIN hivemind_app.hive_communities hc ON hs.community_id = hc.id
UNION ALL
 SELECT hm.block_num,
    hm.post_id,
    16 AS type_id,
    (select hb.created_at from hivemind_app.blocks_view hb where hb.num = (hm.block_num - 1)) as created_at, -- use time of previous block to match head_block_time behavior at given block
    hp.author_id AS src,
    hm.account_id AS dst,
    hm.post_id as dst_post_id,
    ''::character varying(16) AS community,
    ''::character varying AS community_title,
    ''::character varying AS payload
   FROM hivemind_app.hive_mentions hm  -- mentions
   JOIN hivemind_app.hive_posts hp ON hm.post_id = hp.id
) notifs
JOIN hivemind_app.hive_accounts_rank_view harv ON harv.id = notifs.src
;

--vote has own score, new communities score as 35 (magic number), persistent notifications are already scored
DROP VIEW IF EXISTS hivemind_app.hive_raw_notifications_view_no_account_score cascade;
CREATE OR REPLACE VIEW hivemind_app.hive_raw_notifications_view_no_account_score
AS
SELECT -- votes
      vn.block_num
    , vn.post_id
    , vn.type_id
    , vn.created_at
    , vn.src
    , vn.dst
    , vn.dst_post_id
    , vn.community
    , vn.community_title
    , CASE
        WHEN vn.vote_value < 0.01 THEN ''::VARCHAR
        ELSE CAST( to_char(vn.vote_value, '($FM99990.00)') AS VARCHAR )
      END as payload
    , vn.score
FROM
  (
    SELECT
        hv1.block_num
      , hpv.id AS post_id
      , 17 AS type_id
      , hv1.last_update AS created_at
      , hv1.voter_id AS src
      , hpv.author_id AS dst
      , hpv.id AS dst_post_id
      , ''::VARCHAR(16) AS community
      , ''::VARCHAR AS community_title
      , hivemind_app.calculate_value_of_vote_on_post(hpv.payout + hpv.pending_payout, hpv.rshares, hv1.rshares) AS vote_value
      , hivemind_app.calculate_notify_vote_score(hpv.payout + hpv.pending_payout, hpv.abs_rshares, hv1.rshares) AS score
    FROM hivemind_app.hive_votes hv1
    JOIN
      (
        SELECT
            hpvi.id
          , hpvi.author_id
          , hpvi.payout
          , hpvi.pending_payout
          , hpvi.abs_rshares
          , hpvi.vote_rshares as rshares
         FROM hivemind_app.hive_posts hpvi
         WHERE hpvi.block_num > hivemind_app.block_before_head('97 days'::interval)
       ) hpv ON hv1.post_id = hpv.id
    WHERE hv1.rshares >= 10e9
  ) as vn
  WHERE vn.vote_value >= 0.02
UNION ALL
  SELECT -- new community
      hc.block_num as block_num
      , 0 as post_id
      , 1 as type_id
      , hc.created_at as created_at
      , 0 as src
      , hc.id as dst
      , 0 as dst_post_id
      , hc.name as community
      , ''::VARCHAR as community_title
      , ''::VARCHAR as payload
      , 35 as score
  FROM
      hivemind_app.hive_communities hc
UNION ALL
  SELECT --persistent notifs
       hn.block_num
     , hn.post_id as post_id
     , hn.type_id as type_id
     , hn.created_at as created_at
     , hn.src_id as src
     , hn.dst_id as dst
     , hn.post_id as dst_post_id
     , hc.name as community
     , hc.title as community_title
     , hn.payload as payload
     , hn.score as score
  FROM hivemind_app.hive_notifs hn
  JOIN hivemind_app.hive_communities hc ON hn.community_id = hc.id
;

DROP VIEW IF EXISTS hivemind_app.hive_raw_notifications_view CASCADE;
CREATE OR REPLACE VIEW hivemind_app.hive_raw_notifications_view
AS
SELECT *
FROM
  (
  SELECT * FROM hivemind_app.hive_raw_notifications_as_view
  UNION ALL
  SELECT * FROM hivemind_app.hive_raw_notifications_view_no_account_score
  ) as notifs
WHERE notifs.score >= 0 AND notifs.src IS DISTINCT FROM notifs.dst;
