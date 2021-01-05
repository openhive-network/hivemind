DROP VIEW IF EXISTS public.hive_posts_view;

CREATE OR REPLACE VIEW public.hive_posts_view
AS
SELECT hp.id,
  hp.community_id,
  hp.root_id,
  hp.parent_id,
  ha_a.name AS author,
  hp.active,
  hp.author_rewards,
  hp.author_id,
  hpd_p.permlink,
  hpd.title,
  hpd.body,
  hpd.img_url,
  hpd.preview,
  hcd.category,
  hp.category_id,
  hp.depth,
  hp.promoted,
  hp.payout,
  hp.pending_payout,
  hp.payout_at,
  hp.last_payout_at,
  hp.cashout_time,
  hp.is_paidout,
  hp.children,
  0 AS votes,
  0 AS active_votes,
  hp.created_at,
  hp.updated_at,
  hp.vote_rshares AS rshares,
  hp.abs_rshares AS abs_rshares,
  hp.total_votes AS total_votes,
  hp.net_votes as net_votes,
  hpd.json,
  ha_a.reputation AS author_rep,
  hp.is_hidden,
  ha_a.is_grayed,
  hp.total_vote_weight,
  ha_pp.name AS parent_author,
  ha_pp.id AS parent_author_id,
    ( CASE hp.depth > 0
      WHEN True THEN hpd_pp.permlink
      ELSE hcd.category
    END ) AS parent_permlink_or_category,
  hp.curator_payout_value,
  ha_rp.name AS root_author,
  hpd_rp.permlink AS root_permlink,
  rcd.category as root_category,
  hp.max_accepted_payout,
  hp.percent_hbd,
    True AS allow_replies,
  hp.allow_votes,
  hp.allow_curation_rewards,
  hp.beneficiaries,
    CONCAT('/', rcd.category, '/@', ha_rp.name, '/', hpd_rp.permlink,
      CASE (rp.id)
        WHEN hp.id THEN ''
        ELSE CONCAT('#@', ha_a.name, '/', hpd_p.permlink)
      END
    ) AS url,
  rpd.title AS root_title,
  hp.sc_trend,
  hp.sc_hot,
  hp.is_pinned,
  hp.is_muted,
  hp.is_nsfw,
  hp.is_valid,
  hr.title AS role_title,
  hr.role_id AS role_id,
  hc.title AS community_title,
  hc.name AS community_name,
  hp.block_num
  FROM hive_posts hp
    JOIN hive_posts pp ON pp.id = hp.parent_id
    JOIN hive_posts rp ON rp.id = hp.root_id
    JOIN hive_accounts_view ha_a ON ha_a.id = hp.author_id
    JOIN hive_permlink_data hpd_p ON hpd_p.id = hp.permlink_id
    JOIN hive_post_data hpd ON hpd.id = hp.id
    JOIN hive_accounts ha_pp ON ha_pp.id = pp.author_id
    JOIN hive_permlink_data hpd_pp ON hpd_pp.id = pp.permlink_id
    JOIN hive_accounts ha_rp ON ha_rp.id = rp.author_id
    JOIN hive_permlink_data hpd_rp ON hpd_rp.id = rp.permlink_id
    JOIN hive_post_data rpd ON rpd.id = rp.id
    JOIN hive_category_data hcd ON hcd.id = hp.category_id
    JOIN hive_category_data rcd ON rcd.id = rp.category_id
    LEFT JOIN hive_communities hc ON hp.community_id = hc.id
    LEFT JOIN hive_roles hr ON hp.author_id = hr.account_id AND hp.community_id = hr.community_id
  WHERE hp.counter_deleted = 0
  ;
