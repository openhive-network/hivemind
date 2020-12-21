DROP VIEW IF EXISTS public.hive_accounts_rank_view CASCADE;

CREATE OR REPLACE VIEW public.hive_accounts_rank_view
AS
SELECT rank.id,
CASE
  WHEN rank."position" < 200 THEN 70
  WHEN rank."position" < 1000 THEN 60
  WHEN rank."position" < 6500 THEN 50
  WHEN rank."position" < 25000 THEN 40
  WHEN rank."position" < 100000 THEN 30
  ELSE 20
END AS score
FROM
(
  SELECT
    ha.id as id
    , CASE WHEN ha2.rank ISNULL THEN 10e6 ELSE ha2.rank END AS "position"
  FROM
   hive_accounts ha
  LEFT JOIN
  (
    SELECT
      ha3.id
    , rank() OVER(order by ha3.reputation DESC) as rank
    FROM  hive_accounts ha3
    ORDER BY ha3.reputation DESC LIMIT 150000
    -- Conditions above (related to rank.position) eliminates all records having rank > 100k. So with inclding some
    -- additional space for redundant accounts (having same reputation) lets assume we're limiting it to 150k
    -- As another reason, it can be pointed that only 2% of account has the same reputations, it means only 2000
    -- in 100000, but we get 150000 as 50% would repeat
  ) as ha2 ON ha2.id = ha.id
) rank
;

DROP FUNCTION IF EXISTS public.calculate_notify_vote_score(_payout hive_posts.payout%TYPE, _abs_rshares hive_posts_view.abs_rshares%TYPE, _rshares hive_votes.rshares%TYPE) CASCADE
;
CREATE OR REPLACE FUNCTION public.calculate_notify_vote_score(_payout hive_posts.payout%TYPE, _abs_rshares hive_posts_view.abs_rshares%TYPE, _rshares hive_votes.rshares%TYPE)
RETURNS INT
LANGUAGE 'sql'
IMMUTABLE
AS $BODY$
    SELECT CASE
        WHEN ((( _payout )/_abs_rshares) * 1000 * _rshares < 20 ) THEN -1
            ELSE LEAST(100, (LENGTH(CAST( CAST( ( (( _payout )/_abs_rshares) * 1000 * _rshares ) as BIGINT) as text)) - 1) * 25)
    END;
$BODY$;

DROP FUNCTION IF EXISTS notification_id CASCADE;
;
CREATE OR REPLACE FUNCTION notification_id(in _block_number INTEGER, in _notifyType INTEGER, in _id INTEGER)
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

DROP FUNCTION IF EXISTS public.calculate_value_of_vote_on_post CASCADE;
CREATE OR REPLACE FUNCTION public.calculate_value_of_vote_on_post(
    _post_payout hive_posts.payout%TYPE
  , _post_rshares hive_posts_view.rshares%TYPE
  , _vote_rshares hive_votes.rshares%TYPE)
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


-- View: public.hive_raw_notifications_as_view

DROP VIEW IF EXISTS public.hive_raw_notifications_as_view CASCADE;
CREATE OR REPLACE VIEW public.hive_raw_notifications_as_view
 AS
 SELECT notifs.block_num,
    notifs.id,
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
   FROM ( SELECT hpv.block_num,
            notification_id(hpv.block_num,
                CASE hpv.depth
                    WHEN 1 THEN 12
                    ELSE 13
                END, hpv.id) AS id,
            hpv.parent_id AS post_id,
                CASE hpv.depth
                    WHEN 1 THEN 12
                    ELSE 13
                END AS type_id,
            hpv.created_at,
            hpv.author_id AS src,
            hpv.parent_author_id AS dst,
            hpv.parent_id as dst_post_id,
            ''::character varying(16) AS community,
            ''::character varying AS community_title,
            ''::character varying AS payload
           FROM hive_posts_pp_view hpv
                  WHERE hpv.depth > 0 AND
                        NOT EXISTS (SELECT NULL::text
                                    FROM hive_follows hf
                                    WHERE hf.follower = hpv.parent_author_id AND hf.following = hpv.author_id AND hf.state = 2)
UNION ALL
 SELECT hf.block_num,
    notification_id(hf.block_num, 15, hf.id) AS id,
    0 AS post_id,
    15 AS type_id,
    hb.created_at,
    hf.follower AS src,
    hf.following AS dst,
    0 as dst_post_id,
    ''::character varying(16) AS community,
    ''::character varying AS community_title,
    ''::character varying AS payload
   FROM hive_follows hf
   JOIN hive_blocks hb ON hf.block_num = hb.num
   WHERE hf.state = 1 --only follow blog

UNION ALL
 SELECT hr.block_num,
    notification_id(hr.block_num, 14, hr.id) AS id,
    hp.id AS post_id,
    14 AS type_id,
    hr.created_at,
    hr.blogger_id AS src,
    hp.author_id AS dst,
    hr.post_id as dst_post_id,
    ''::character varying(16) AS community,
    ''::character varying AS community_title,
    ''::character varying AS payload
   FROM hive_reblogs hr
   JOIN hive_posts hp ON hr.post_id = hp.id
UNION ALL
 SELECT hs.block_num,
    notification_id(hs.block_num, 11, hs.id) AS id,
    0 AS post_id,
    11 AS type_id,
    hs.created_at,
    hs.account_id AS src,
    hs.community_id AS dst,
    0 as dst_post_id,
    hc.name AS community,
    hc.title AS community_title,
    ''::character varying AS payload
   FROM hive_subscriptions hs
   JOIN hive_communities hc ON hs.community_id = hc.id
UNION ALL
 SELECT hm.block_num,
    notification_id(hm.block_num, 16, hm.id) AS id,
    hm.post_id,
    16 AS type_id,
    hp.created_at,
    hp.author_id AS src,
    hm.account_id AS dst,
    hm.post_id as dst_post_id,
    ''::character varying(16) AS community,
    ''::character varying AS community_title,
    ''::character varying AS payload
   FROM hive_mentions hm
   JOIN hive_posts hp ON hm.post_id = hp.id
) notifs
JOIN hive_accounts_rank_view harv ON harv.id = notifs.src
;

DROP VIEW IF EXISTS hive_raw_notifications_view_noas cascade;
CREATE OR REPLACE VIEW hive_raw_notifications_view_noas
AS
SELECT -- votes
      vn.block_num
    , vn.id
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
      , notification_id(hv1.block_num, 17, hv1.id::integer) AS id
      , hpv.id AS post_id
      , 17 AS type_id
      , hv1.last_update AS created_at
      , hv1.voter_id AS src
      , hpv.author_id AS dst
      , hpv.id AS dst_post_id
      , ''::VARCHAR(16) AS community
      , ''::VARCHAR AS community_title
      , calculate_value_of_vote_on_post(hpv.payout + hpv.pending_payout, hpv.rshares, hv1.rshares) AS vote_value
      , calculate_notify_vote_score(hpv.payout + hpv.pending_payout, hpv.abs_rshares, hv1.rshares) AS score
    FROM hive_votes hv1
    JOIN
      (
        SELECT
            hpvi.id
          , hpvi.author_id
          , hpvi.payout
          , hpvi.pending_payout
          , hpvi.abs_rshares
          , hpvi.vote_rshares as rshares
         FROM hive_posts hpvi
         WHERE hpvi.block_num > block_before_head('97 days'::interval)
       ) hpv ON hv1.post_id = hpv.id
    WHERE hv1.rshares >= 10e9
  ) as vn
  WHERE vn.vote_value >= 0.02
UNION ALL
  SELECT -- new community
      hc.block_num as block_num
      , notification_id(hc.block_num, 11, hc.id) as id
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
      hive_communities hc
UNION ALL
  SELECT --persistent notifs
       hn.block_num
     , notification_id(hn.block_num, hn.type_id, CAST( hn.id as INT) ) as id
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
  FROM hive_notifs hn
  JOIN hive_communities hc ON hn.community_id = hc.id
;

DROP VIEW IF EXISTS hive_raw_notifications_view CASCADE;
CREATE OR REPLACE VIEW hive_raw_notifications_view
AS
SELECT *
FROM
  (
  SELECT * FROM hive_raw_notifications_as_view
  UNION ALL
  SELECT * FROM hive_raw_notifications_view_noas
  ) as notifs
WHERE notifs.score >= 0;
