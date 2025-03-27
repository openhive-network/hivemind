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
  SELECT * FROM hivemind_app.hive_raw_notifications_view_no_account_score
  ) as notifs
WHERE notifs.score >= 0 AND notifs.src IS DISTINCT FROM notifs.dst;
