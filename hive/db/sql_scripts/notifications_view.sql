DROP VIEW IF EXISTS hive_notifications_view
;
CREATE VIEW hive_notifications_view
AS
SELECT
*
FROM
(
  SELECT --replies
        posts_and_scores.block_num as block_num
      , posts_and_scores.id as id
      , posts_and_scores.post_id as post_id
      , posts_and_scores.type_id as type_id
      , posts_and_scores.created_at as created_at
      , posts_and_scores.author as src
      , posts_and_scores.parent_author as dst
      , posts_and_scores.parent_author as author
      , posts_and_scores.parent_permlink as permlink
      , ''::VARCHAR as community
      , ''::VARCHAR as community_title
      , ''::VARCHAR as payload
      , posts_and_scores.score as score
	    , posts_and_scores.parent_author_id as dst_id
  FROM
  (
      SELECT
            hpv.block_num as block_num
          , notification_id(
                hpv.block_num
              , CASE ( hpv.depth )
                  WHEN 1 THEN 12 --replies
                  ELSE 13 --comment replies
                END
              , hpv.id ) as id
          , CASE ( hpv.depth )
              WHEN 1 THEN 12 --replies
              ELSE 13 --comment replies
            END as type_id
          , hpv.created_at
          , hpv.author
          , hpv.parent_id as post_id
          , hpv.parent_author as parent_author
          , hpv.parent_permlink_or_category as parent_permlink
          , hpv.depth
          , hpv.parent_author_id
          , hpv.author_id
          , harv.score as score
      FROM
      (
		SELECT hpv2.*
		FROM hive_posts_view hpv2
		WHERE hpv2.block_num > block_before_head( '90 days' )
	) as hpv
      JOIN hive_accounts_rank_view harv ON harv.id = hpv.author_id
      WHERE hpv.depth > 0
  ) as posts_and_scores
  WHERE NOT EXISTS(
      SELECT 1
      FROM
      hive_follows hf
      WHERE hf.follower = posts_and_scores.parent_author_id AND hf.following = posts_and_scores.author_id AND hf.state = 2
  )
UNION ALL
  SELECT --follows
        hf.block_num as block_num
      , notifs_id.notif_id as id
      , 0 as post_id
      , 15 as type_id
      , hf.created_at as created_at
      , followers_scores.follower_name as src
      , ha2.name as dst
      , ''::VARCHAR as author
      , ''::VARCHAR as permlink
      , ''::VARCHAR as community
      , ''::VARCHAR as community_title
      , ''::VARCHAR as payload
      , followers_scores.score as score
	, ha2.id as dst_id
  FROM
	hive_follows hf
  JOIN hive_accounts ha2 ON hf.following = ha2.id
  JOIN (
      SELECT
            ha.id as follower_id
          , ha.name as follower_name
          , harv.score as score
      FROM hive_accounts ha
      JOIN hive_accounts_rank_view harv ON harv.id = ha.id
  ) as followers_scores ON followers_scores.follower_id = hf.follower
  JOIN (
      SELECT
            hf2.id as id
          , notification_id(hf2.block_num, 15, hf2.id) as notif_id
      FROM hive_follows hf2
  ) as notifs_id ON notifs_id.id = hf.id
UNION ALL
  SELECT --reblogs
        hr.block_num as block_num
      , hr_scores.notif_id as id
      , hp.id as post_id
      , 14 as type_id
      , hr.created_at as created_at
      , ha_hr.name as src
      , ha.name as dst
      , ha.name as author
      , hpd.permlink as permlink
      , ''::VARCHAR as community
      , ''::VARCHAR as community_title
      , ''::VARCHAR as payload
      , hr_scores.score as score
	    , ha.id as dst_id
  FROM
      hive_reblogs hr
  JOIN hive_posts hp ON hr.post_id = hp.id
  JOIN hive_permlink_data hpd ON hp.permlink_id = hpd.id
  JOIN hive_accounts ha_hr ON hr.blogger_id = ha_hr.id
  JOIN (
      SELECT
            hr2.id as id
          , notification_id(hr2.block_num, 14, hr2.id) as notif_id
          , harv.score as score
      FROM hive_reblogs hr2
      JOIN hive_accounts_rank_view harv ON harv.id = hr2.blogger_id
  ) as hr_scores ON hr_scores.id = hr.id
  JOIN hive_accounts ha ON hp.author_id = ha.id
  UNION ALL
  SELECT --subscriptions
        hs.block_num as block_num
      , hs_scores.notif_id as id
      , 0 as post_id
      , 11 as type_id
      , hs.created_at as created_at
      , hs_scores.src as src
      , ha_com.name as dst
      , ''::VARCHAR as author
      , ''::VARCHAR as permlink
      , hc.name as community
      , hc.title as community_title
      , ''::VARCHAR as payload
      , hs_scores.score
	    , ha_com.id as dst_id
  FROM
      hive_subscriptions hs
  JOIN hive_communities hc ON hs.community_id = hc.id
  JOIN (
      SELECT
            hs2.id as id
          , notification_id(hs2.block_num, 11, hs2.id) as notif_id
          , harv.score as score
          , ha.name as src
      FROM hive_subscriptions hs2
      JOIN hive_accounts ha ON hs2.account_id = ha.id
      JOIN hive_accounts_rank_view harv ON harv.id = ha.id
  ) as hs_scores ON hs_scores.id = hs.id
  JOIN hive_accounts ha_com ON hs.community_id = ha_com.id
UNION ALL
  SELECT -- new community
        hc.block_num as block_num
      , hc_id.notif_id as id
      , 0 as post_id
      , 1 as type_id
      , hc.created_at as created_at
      , ''::VARCHAR as src
      , ha.name as dst
      , ''::VARCHAR as author
      , ''::VARCHAR as permlink
      , hc.name as community
      , ''::VARCHAR as community_title
      , ''::VARCHAR as payload
      , 35 as score
	, ha.id as dst_id
  FROM
      hive_communities hc
  JOIN hive_accounts ha ON ha.id = hc.id
  JOIN (
      SELECT
            hc2.id as id
          , notification_id(hc2.block_num, 11, hc2.id) as notif_id
      FROM  hive_communities hc2
  ) as hc_id ON hc_id.id = hc.id
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
      , ''::VARCHAR as community
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
      FROM hive_votes hv1
      JOIN (
		SELECT hpv2.*
		FROM hive_posts_view hpv2
		WHERE hpv2.block_num > block_before_head( '90 days' )
	) as hpv ON hv1.post_id = hpv.id
      JOIN hive_accounts ha ON ha.id = hv1.voter_id
      WHERE hv1.rshares >= 10e9 AND hpv.abs_rshares != 0
  ) as scores
  WHERE scores.score > 0
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
    , '' as community
    , '' as community_title
    , '' as payload
    , harv.score as score
    , ha_dst.id as dst_id
  FROM hive_mentions hm
  JOIN hive_accounts ha_dst ON hm.account_id = ha_dst.id
  LEFT JOIN hive_posts hp ON hm.post_id = hp.id
  LEFT JOIN hive_accounts ha_pst ON ha_pst.id = hp.author_id
  LEFT JOIN hive_permlink_data hpd ON hpd.id = hp.permlink_id
  JOIN hive_accounts_rank_view harv ON harv.id = ha_dst.id
) as notifs
WHERE notifs.block_num >= block_before_head( '90 days' );
