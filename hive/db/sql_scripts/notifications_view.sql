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

DROP FUNCTION IF EXISTS notification_id(in _block_number INTEGER, in _notifyType INTEGER, in _id INTEGER)
;
CREATE OR REPLACE FUNCTION notification_id(in _block_number INTEGER, in _notifyType INTEGER, in _id INTEGER)
RETURNS BIGINT
AS
$function$
BEGIN
RETURN CAST( _block_number as BIGINT ) << 32
       | ( _notifyType << 16 )
       | ( _id & CAST( x'0000FFFF' as INTEGER) );
END
$function$
LANGUAGE plpgsql IMMUTABLE
;


DROP VIEW IF EXISTS hive_accounts_rank_view CASCADE
;
CREATE OR REPLACE VIEW hive_accounts_rank_view
AS
SELECT
    ha.id as id
  , CASE
         WHEN rank.position < 200 THEN 70
         WHEN rank.position < 1000 THEN 60
         WHEN rank.position < 6500 THEN 50
         WHEN rank.position < 25000 THEN 40
         WHEN rank.position < 100000 THEN 30
         ELSE 20
     END as score
FROM hive_accounts ha
JOIN (
SELECT ha2.id, RANK () OVER ( ORDER BY ha2.reputation DESC ) as position FROM hive_accounts ha2
) as rank ON ha.id = rank.id
;

DROP VIEW IF EXISTS hive_notifications_view
;
CREATE OR REPLACE VIEW hive_notifications_view
AS
SELECT
*
FROM
(
  SELECT --replies
		hpv.block_num as block_num
	  , notification_id(
			hpv.block_num
		 , CASE ( hpv.depth )
			  WHEN 1 THEN 12 --replies
			  ELSE 13 --comment replies
			END
		  , hpv.id ) as id
	  , hpv.parent_id as post_id
	  , CASE ( hpv.depth )
		  WHEN 1 THEN 12 --replies
		  ELSE 13 --comment replies
		END as type_id
	  , hpv.created_at as created_at
	  , hpv.author as src
	  , hpv.parent_author as dst
	  , hpv.parent_author as author
	  , hpv.parent_permlink_or_category as permlink
	  , ''::VARCHAR(16) as community
    , ''::VARCHAR as community_title
    , ''::VARCHAR as payload
	  , harv.score as score
	  , hpv.parent_author_id as dst_id
  FROM ( SELECT * FROM hive_posts_view hpvi WHERE hpvi.block_num >= block_before_head( '90 days' ) ) as hpv
  JOIN hive_accounts_rank_view harv ON harv.id = hpv.author_id
  LEFT JOIN ( SELECT hf.follower, hf.following FROM hive_follows hf WHERE hf.state = 2  ) as follows
	ON hpv.parent_author_id = follows.follower AND hpv.author_id = follows.following
  WHERE hpv.depth > 0 AND follows.follower IS NULL
UNION ALL
  SELECT --follows
        hf.block_num as block_num
      , notification_id(hf.block_num, 15, hf.id) as id
      , 0 as post_id
      , 15 as type_id
      , hf.created_at as created_at
      , ha3.name as src
      , ha2.name as dst
      , ''::VARCHAR(16) as author
      , ''::VARCHAR as permlink
      , ''::VARCHAR(16) as community
      , ''::VARCHAR as community_title
      , ''::VARCHAR as payload
      , harv.score as score
	  , ha2.id as dst_id
  FROM hive_follows hf
  JOIN hive_accounts ha2 ON hf.following = ha2.id
  JOIN hive_accounts ha3 ON hf.follower = ha3.id
  JOIN hive_accounts_rank_view harv ON harv.id = ha3.id
UNION ALL
  SELECT --reblogs
        hr.block_num as block_num
      , notification_id(hr.block_num, 14, hr.id) as id
      , hp.id as post_id
      , 14 as type_id
      , hr.created_at as created_at
      , ha_hr.name as src
      , ha.name as dst
      , ha.name as author
      , hpd.permlink as permlink
      , ''::VARCHAR(16) as community
      , ''::VARCHAR as community_title
      , ''::VARCHAR as payload
      , harv.score as score
	  , ha.id as dst_id
  FROM hive_reblogs hr
  JOIN hive_posts hp ON hr.post_id = hp.id
  JOIN hive_permlink_data hpd ON hp.permlink_id = hpd.id
  JOIN hive_accounts ha_hr ON hr.blogger_id = ha_hr.id
  JOIN hive_accounts_rank_view harv ON harv.id = hr.blogger_id
  JOIN hive_accounts ha ON hp.author_id = ha.id
UNION ALL
  SELECT --subscriptions
        hs.block_num as block_num
      , notification_id(hs.block_num, 11, hs.id) as id
      , 0 as post_id
      , 11 as type_id
      , hs.created_at as created_at
      , ha.name as src
      , ha_com.name as dst
      , ''::VARCHAR(16) as author
      , ''::VARCHAR as permlink
      , hc.name as community
      , hc.title as community_title
      , ''::VARCHAR as payload
      , harv.score as score
	  , ha_com.id as dst_id
  FROM hive_subscriptions hs
  JOIN hive_communities hc ON hs.community_id = hc.id
  JOIN hive_accounts ha ON hs.account_id = ha.id
  JOIN hive_accounts_rank_view harv ON harv.id = ha.id
  JOIN hive_accounts ha_com ON hs.community_id = ha_com.id
UNION ALL
  SELECT -- new community
        hc.block_num as block_num
      , notification_id(hc.block_num, 11, hc.id) as id
      , 0 as post_id
      , 1 as type_id
      , hc.created_at as created_at
      , ''::VARCHAR(16) as src
      , ha.name as dst
      , ''::VARCHAR(16) as author
      , ''::VARCHAR as permlink
      , hc.name as community
      , ''::VARCHAR as community_title
      , ''::VARCHAR as payload
      , 35 as score
	, ha.id as dst_id
  FROM
      hive_communities hc
  JOIN hive_accounts ha ON ha.id = hc.id
UNION ALL
  SELECT --votes
        scores.block_num as block_num
      , scores.notif_id as id
      , scores.post_id as post_id
      , 17 as type_id
      , scores.last_update as created_at
      , scores.src as src
      , scores.dst as dst
      , scores.dst as author
      , scores.permlink as permlink
      , ''::VARCHAR(16) as community
      , ''::VARCHAR as community_title
      , ''::VARCHAR as payload
      , scores.score as score
	  , scores.dst_id as dst_id
  FROM
  (
      SELECT
            hv1.block_num
          , hv1.id as id
          , hpv.id as post_id
          , notification_id(hv1.block_num, 17, CAST( hv1.id as INT) ) as notif_id
          , calculate_notify_vote_score( (hpv.payout + hpv.pending_payout), hpv.abs_rshares, hv1.rshares ) as score
          , hpv.author as dst
          , ha.name as src
          , hpv.permlink as permlink
          , hv1.last_update
		  , hpv.author_id as dst_id
      FROM (SELECT * FROM hive_votes hvi WHERE hvi.block_num > block_before_head( '90 days' ) ) as hv1
      JOIN (SELECT * FROM hive_posts_view hpvi WHERE hpvi.block_num > block_before_head( '97 days' ) ) as hpv ON hv1.post_id = hpv.id
      JOIN hive_accounts ha ON ha.id = hv1.voter_id
      WHERE hv1.rshares >= 10e9
  ) as scores
UNION ALL
  SELECT --persistent notifs
       hn.block_num
     , notification_id(hn.block_num, hn.type_id, CAST( hn.id as INT) ) as id
     , hp.id as post_id
     , hn.type_id as type_id
     , hn.created_at as created_at
     , ha_src.name as src
     , ha_dst.name as dst
     , ha_pst.name as author
     , hpd.permlink as permlink
     , hc.name as community
     , hc.title as community_title
     , hn.payload as payload
     , hn.score as score
     , ha_dst.id as dst_id
  FROM hive_notifs hn
  JOIN hive_accounts ha_dst ON hn.dst_id = ha_dst.id
  LEFT JOIN hive_accounts ha_src ON hn.src_id = ha_src.id
  LEFT JOIN hive_communities hc ON hn.community_id = hc.id
  LEFT JOIN hive_posts hp ON hn.post_id = hp.id
  LEFT JOIN hive_accounts ha_pst ON ha_pst.id = hp.author_id
  LEFT JOIN hive_permlink_data hpd ON hpd.id = hp.permlink_id
UNION All
  SELECT --mentions notifs
	  hm.block_num as block_num
    , notification_id(hm.block_num, 16, CAST( hm.id as INT) ) as id
    , hm.post_id as post_id
    , 16 as type_id
   , hp.created_at as created_at
    , ha_pst.name as src
    , ha_dst.name as dst
    , ha_pst.name as author
    , hpd.permlink as permlink
    , ''::VARCHAR(16) as community
    , '' as community_title
    , '' as payload
    , harv.score as score
    , ha_dst.id as dst_id
  FROM hive_mentions hm
  JOIN hive_accounts ha_dst ON hm.account_id = ha_dst.id
  LEFT JOIN hive_posts hp ON hm.post_id = hp.id
  LEFT JOIN hive_accounts ha_pst ON ha_pst.id = hp.author_id
  LEFT JOIN hive_permlink_data hpd ON hpd.id = hp.permlink_id
  JOIN hive_accounts_rank_view harv ON harv.id = ha_pst.id
) as notifs
WHERE notifs.block_num >= block_before_head( '90 days' ) AND notifs.score >= 0;
