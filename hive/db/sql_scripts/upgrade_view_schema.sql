CREATE OR REPLACE VIEW hive_votes_view
AS
SELECT
    hv.id,
    hv.voter_id as voter_id,
    ha_a.name as author,
    hpd.permlink as permlink,
    vote_percent as percent,
    ha_v.reputation as reputation,
    rshares,
    last_update,
    ha_v.name as voter,
    weight,
    num_changes,
    hv.permlink_id as permlink_id,
    post_id,
    is_effective
FROM
    hive_votes hv
INNER JOIN hive_accounts ha_v ON ha_v.id = hv.voter_id
INNER JOIN hive_accounts ha_a ON ha_a.id = hv.author_id
INNER JOIN hive_permlink_data hpd ON hpd.id = hv.permlink_id
;

CREATE OR REPLACE VIEW public.hive_accounts_info_view
AS
SELECT
  id,
  name,
  (
    select count(*) post_count
    FROM hive_posts hp
    WHERE ha.id=hp.author_id
  ) post_count,
  created_at,
  (
    SELECT GREATEST
    (
      created_at,
      COALESCE(
        (
          select max(hp.created_at + '0 days'::interval)
          FROM hive_posts hp
          WHERE ha.id=hp.author_id
        ),
        '1970-01-01 00:00:00.0'
      ),
      COALESCE(
        (
          select max(hv.last_update + '0 days'::interval)
          from hive_votes hv
          WHERE ha.id=hv.voter_id
        ),
        '1970-01-01 00:00:00.0'
      )
    )
  ) active_at,
  reputation,
  rank,
  following,
  followers,
  lastread_at,
  posting_json_metadata,
  json_metadata,
  blacklist_description,
  muted_list_description
FROM
  hive_accounts ha
  ;

CREATE OR REPLACE VIEW public.hive_accounts_view
AS
SELECT id,
  name,
  created_at,
  reputation,
  is_implicit,
  followers,
  following,
  rank,
  lastread_at,
  posting_json_metadata,
  json_metadata,
  ( reputation <= -464800000000 ) AS is_grayed -- biggest number where rep_log10 gives < 1.0
  FROM hive_accounts
;

SELECT deps_save_and_drop_dependencies('public', 'hive_posts_view', true);

DROP VIEW IF EXISTS public.hive_posts_view CASCADE;
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
    COALESCE(
      (
        SELECT SUM( v.rshares )
        FROM hive_votes v
        WHERE v.post_id = hp.id
        GROUP BY v.post_id
      ), 0
    ) AS rshares,
    COALESCE(
      (
        SELECT SUM( CASE v.rshares >= 0 WHEN True THEN v.rshares ELSE -v.rshares END )
        FROM hive_votes v
        WHERE v.post_id = hp.id AND NOT v.rshares = 0
        GROUP BY v.post_id
      ), 0
    ) AS abs_rshares,
    COALESCE(
      (
        SELECT COUNT( 1 )
        FROM hive_votes v
        WHERE v.post_id = hp.id AND v.is_effective
        GROUP BY v.post_id
      ), 0
    ) AS total_votes,
    COALESCE(
      (
        SELECT SUM( CASE v.rshares > 0 WHEN True THEN 1 ELSE -1 END )
        FROM hive_votes v
        WHERE v.post_id = hp.id AND NOT v.rshares = 0
        GROUP BY v.post_id
      ), 0
    ) AS net_votes,
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

SELECT deps_restore_dependencies('public', 'hive_posts_view');

