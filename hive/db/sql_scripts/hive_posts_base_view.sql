DROP VIEW IF EXISTS hivemind_app.hive_posts_base_view cascade;
CREATE OR REPLACE VIEW hivemind_app.hive_posts_base_view
AS
SELECT
      hp.block_num
    , hp.id
    , hp.author_id
    , hp.permlink_id
    , hp.payout
    , hp.pending_payout
    , hp.abs_rshares
    , hp.vote_rshares AS rshares
FROM hivemind_app.hive_posts hp
;

DROP VIEW IF EXISTS hivemind_app.hive_posts_pp_view CASCADE;

CREATE OR REPLACE VIEW hivemind_app.hive_posts_pp_view
 AS
 SELECT hp.id,
    hp.community_id,
    hp.root_id,
    hp.parent_id,
    hp.active,
    hp.author_rewards,
    hp.author_id,
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
    hp.is_hidden,
    hp.total_vote_weight,
    pp.author_id AS parent_author_id,
        CASE hp.depth > 0
            WHEN true THEN hpd_pp.permlink
            ELSE hcd.category
        END AS parent_permlink_or_category,
    hp.curator_payout_value,
    hp.max_accepted_payout,
    hp.percent_hbd,
    true AS allow_replies,
    hp.allow_votes,
    hp.allow_curation_rewards,
    hp.beneficiaries,
    hp.sc_trend,
    hp.sc_hot,
    hp.is_pinned,
    hp.is_muted,
    hp.is_nsfw,
    hp.is_valid,
    hp.block_num
   FROM hivemind_app.hive_posts hp
     JOIN hivemind_app.hive_posts pp ON pp.id = hp.parent_id
     JOIN hivemind_app.hive_permlink_data hpd_pp ON hpd_pp.id = pp.permlink_id
     JOIN hivemind_app.hive_category_data hcd ON hcd.id = hp.category_id
  WHERE hp.counter_deleted = 0 AND hp.id <> 0
  ;
