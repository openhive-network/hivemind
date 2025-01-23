DROP TYPE IF EXISTS hivemind_app.get_post_view_by_id_return_t CASCADE;

CREATE TYPE hivemind_app.get_post_view_by_id_return_t AS(
  id integer,
  community_id integer,
  root_id integer,
  parent_id integer,
  author character varying(16) COLLATE pg_catalog."C",
  active timestamp without time zone,
  author_rewards bigint,
  author_id integer,
  permlink character varying(255) COLLATE pg_catalog."C",
  title character varying(512),
  body text,
  img_url character varying(1024),
  category character varying(255) COLLATE pg_catalog."C",
  category_id integer,
  depth smallint,
  payout numeric(10,3),
  pending_payout numeric(10,3),
  payout_at timestamp without time zone,
  last_payout_at timestamp without time zone,
  cashout_time timestamp without time zone,
  is_paidout boolean,
  children integer,
  votes integer,
  active_votes integer,
  created_at timestamp without time zone,
  updated_at timestamp without time zone,
  rshares numeric,
  abs_rshares numeric,
  total_votes bigint,
  net_votes bigint,
  json text,
  author_rep bigint,
  is_hidden boolean,
  is_grayed boolean,
  total_vote_weight numeric,
  parent_author character varying(16) COLLATE pg_catalog."C",
  parent_author_id integer,
  parent_permlink_or_category character varying(255) COLLATE pg_catalog."C",
  curator_payout_value character varying(30),
  root_author character varying(16) COLLATE pg_catalog."C",
  root_permlink character varying(255) COLLATE pg_catalog."C",
  root_category character varying(255) COLLATE pg_catalog."C",
  max_accepted_payout character varying(30),
  percent_hbd integer,
  allow_replies boolean,
  allow_votes boolean,
  allow_curation_rewards boolean,
  beneficiaries json,
  url text COLLATE pg_catalog."C",
  root_title character varying(512),
  sc_trend real,
  sc_hot real,
  is_pinned boolean,
  is_muted boolean,
  is_nsfw boolean,
  is_valid boolean,
  role_title character varying(140),
  role_id smallint,
  community_title character varying(32),
  community_name character varying(16) COLLATE pg_catalog."C",
  block_num integer,
  muted_reasons INTEGER
);

CREATE OR REPLACE FUNCTION hivemind_app.get_post_view_by_id(_id hivemind_app.hive_posts.id%TYPE) RETURNS SETOF hivemind_app.get_post_view_by_id_return_t
AS $function$
BEGIN 
  RETURN QUERY
  SELECT -- get_post_view_by_id
    hp.id,
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
    hcd.category,
    hp.category_id,
    hp.depth,
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
    hp.abs_rshares,
    hp.total_votes,
    hp.net_votes,
    hpd.json,
    ha_a.reputation AS author_rep,
    hp.is_hidden,
    ha_a.is_grayed,
    hp.total_vote_weight,
    ha_pp.name AS parent_author,
    ha_pp.id AS parent_author_id,
        CASE hp.depth > 0
            WHEN true THEN hpd_pp.permlink
            ELSE hcd.category
        END AS parent_permlink_or_category,
    hp.curator_payout_value,
    ha_rp.name AS root_author,
    hpd_rp.permlink AS root_permlink,
    rcd.category AS root_category,
    hp.max_accepted_payout,
    hp.percent_hbd,
    true AS allow_replies,
    hp.allow_votes,
    hp.allow_curation_rewards,
    hp.beneficiaries,
    concat('/', rcd.category, '/@', ha_rp.name, '/', hpd_rp.permlink,
        CASE rp.id
            WHEN hp.id THEN ''::text
            ELSE concat('#@', ha_a.name, '/', hpd_p.permlink)
        END) AS url,
    rpd.title AS root_title,
    hp.sc_trend,
    hp.sc_hot,
    hp.is_pinned,
    hp.is_muted,
    hp.is_nsfw,
    hp.is_valid,
    hr.title AS role_title,
    hr.role_id,
    hc.title AS community_title,
    hc.name AS community_name,
    hp.block_num,
    hp.muted_reasons
   FROM hivemind_app.hive_posts hp
     -- post data (6 joins)
     JOIN hivemind_app.hive_accounts_view ha_a ON ha_a.id = hp.author_id
     JOIN hivemind_app.hive_category_data hcd ON hcd.id = hp.category_id
     JOIN hivemind_app.hive_permlink_data hpd_p ON hpd_p.id = hp.permlink_id
     LEFT JOIN hivemind_app.hive_communities hc ON hp.community_id = hc.id
     LEFT JOIN hivemind_app.hive_roles hr ON hp.author_id = hr.account_id AND hp.community_id = hr.community_id
     -- parent post data 
     JOIN hivemind_app.hive_posts pp ON pp.id = hp.parent_id -- parent post (0 or 1 parent)
     JOIN hivemind_app.hive_accounts ha_pp ON ha_pp.id = pp.author_id
     JOIN hivemind_app.hive_permlink_data hpd_pp ON hpd_pp.id = pp.permlink_id
     -- root post data
     JOIN hivemind_app.hive_posts rp ON rp.id = hp.root_id -- root_post (0 or 1 root)
     JOIN hivemind_app.hive_accounts ha_rp ON ha_rp.id = rp.author_id
     JOIN hivemind_app.hive_permlink_data hpd_rp ON hpd_rp.id = rp.permlink_id
     JOIN hivemind_app.hive_category_data rcd ON rcd.id = rp.category_id
     JOIN hivemind_app.hive_post_data rpd ON rpd.id = rp.id
     -- largest joined data
     JOIN hivemind_app.hive_post_data hpd ON hpd.id = hp.id
  WHERE hp.id = _id AND hp.counter_deleted = 0;
END;
$function$ LANGUAGE plpgsql STABLE SET join_collapse_limit = 6;
--Changed join_collapse_limit from 1 to 6. Testing on a node with 5 million blocks showed a significant 
--improvement in performance for joins between hive.accounts_view and reptracker_app.account_reputations,
--reducing query time from 200ms to 12ms

CREATE OR REPLACE FUNCTION hivemind_app.get_blacklisted_by_observer(_observer_id INTEGER)
RETURNS TABLE (
    blacklisted_id INTEGER,
    source TEXT
) AS $$
BEGIN
    IF _observer_id = 0 THEN
        RETURN QUERY SELECT NULL::INTEGER AS blacklisted_id, NULL::TEXT AS source WHERE FALSE;
    ELSE
        RETURN QUERY
        WITH blacklisters AS MATERIALIZED  --all blacklists followed by account
        (
          SELECT following as id FROM hivemind_app.hive_follows WHERE follow_blacklists AND follower = _observer_id -- hive_follows_follower_where_follow_blacklists_idx
        ),
        indirects AS MATERIALIZED             -- get all indirectly blacklisted accounts with the ids of their sources
        (
          SELECT blacklister_follows.following AS blacklisted_id,
                 blacklister_follows.follower AS blacklister_id
          FROM blacklisters
          JOIN hivemind_app.hive_follows blacklister_follows ON blacklister_follows.follower = blacklisters.id -- need this to get all accounts blacklisted by blacklister
          WHERE blacklister_follows.blacklisted  --hive_follows_follower_where_blacklisted_idx
        )
        SELECT following AS blacklisted_id,        -- directly blacklisted accounts
               'my blacklist'::text AS source
        FROM hivemind_app.hive_follows
        WHERE hive_follows.blacklisted AND hive_follows.follower = _observer_id  --hive_follows_follower_where_blacklisted_idx
        UNION ALL
        SELECT indirects.blacklisted_id AS blacklisted_id,                       -- collapse duplicate indirectly blacklisted accounts and aggreagate their sources
               string_agg('blacklisted by '::text || blacklister_accounts.name::text, ','::text ORDER BY blacklister_accounts.name) AS source
        FROM indirects
        JOIN hivemind_app.hive_accounts blacklister_accounts ON blacklister_accounts.id = indirects.blacklister_id    -- need this to get name of blacklister, use hive_accounts_ux1
        GROUP BY indirects.blacklisted_id;
    END IF;
END;
$$ LANGUAGE plpgsql STABLE;

DROP TYPE IF EXISTS hivemind_app.get_full_post_view_by_id_return_t CASCADE;
CREATE TYPE hivemind_app.get_full_post_view_by_id_return_t AS(
  id integer,
  community_id integer,
  root_id integer,
  parent_id integer,
  author character varying(16) COLLATE pg_catalog."C",
  active timestamp without time zone,
  author_rewards bigint,
  author_id integer,
  permlink character varying(255) COLLATE pg_catalog."C",
  title character varying(512),
  body text,
  img_url character varying(1024),
  category character varying(255) COLLATE pg_catalog."C",
  category_id integer,
  depth smallint,
  payout numeric(10,3),
  pending_payout numeric(10,3),
  payout_at timestamp without time zone,
  last_payout_at timestamp without time zone,
  cashout_time timestamp without time zone,
  is_paidout boolean,
  children integer,
  votes integer,
  active_votes integer,
  created_at timestamp without time zone,
  updated_at timestamp without time zone,
  rshares numeric,
  abs_rshares numeric,
  total_votes bigint,
  net_votes bigint,
  json text,
  author_rep bigint,
  is_hidden boolean,
  is_grayed boolean,
  total_vote_weight numeric,
  parent_author character varying(16) COLLATE pg_catalog."C",
  parent_author_id integer,
  parent_permlink_or_category character varying(255) COLLATE pg_catalog."C",
  curator_payout_value character varying(30),
  root_author character varying(16) COLLATE pg_catalog."C",
  root_permlink character varying(255) COLLATE pg_catalog."C",
  root_category character varying(255) COLLATE pg_catalog."C",
  max_accepted_payout character varying(30),
  percent_hbd integer,
  allow_replies boolean,
  allow_votes boolean,
  allow_curation_rewards boolean,
  beneficiaries json,
  url text COLLATE pg_catalog."C",
  root_title character varying(512),
  sc_trend real,
  sc_hot real,
  is_pinned boolean,
  is_muted boolean,
  is_nsfw boolean,
  is_valid boolean,
  role_title character varying(140),
  role_id smallint,
  community_title character varying(32),
  community_name character varying(16) COLLATE pg_catalog."C",
  block_num integer,
  muted_reasons INTEGER,
  source TEXT
);

CREATE OR REPLACE FUNCTION hivemind_app.get_full_post_view_by_id(_id hivemind_app.hive_posts.id%TYPE, _observer_id INTEGER) RETURNS SETOF hivemind_app.get_full_post_view_by_id_return_t
AS $function$
BEGIN 
  RETURN QUERY
  SELECT -- get_full_post_view_by_id
    hp.id,
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
    hcd.category,
    hp.category_id,
    hp.depth,
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
    hp.abs_rshares,
    hp.total_votes,
    hp.net_votes,
    hpd.json,
    ha_a.reputation AS author_rep,
    hp.is_hidden,
    ha_a.is_grayed,
    hp.total_vote_weight,
    ha_pp.name AS parent_author,
    ha_pp.id AS parent_author_id,
        CASE hp.depth > 0
            WHEN true THEN hpd_pp.permlink
            ELSE hcd.category
        END AS parent_permlink_or_category,
    hp.curator_payout_value,
    ha_rp.name AS root_author,
    hpd_rp.permlink AS root_permlink,
    rcd.category AS root_category,
    hp.max_accepted_payout,
    hp.percent_hbd,
    true AS allow_replies,
    hp.allow_votes,
    hp.allow_curation_rewards,
    hp.beneficiaries,
    concat('/', rcd.category, '/@', ha_rp.name, '/', hpd_rp.permlink,
        CASE rp.id
            WHEN hp.id THEN ''::text
            ELSE concat('#@', ha_a.name, '/', hpd_p.permlink)
        END) AS url,
    rpd.title AS root_title,
    hp.sc_trend,
    hp.sc_hot,
    hp.is_pinned,
    hp.is_muted,
    hp.is_nsfw,
    hp.is_valid,
    hr.title AS role_title,
    hr.role_id,
    hc.title AS community_title,
    hc.name AS community_name,
    hp.block_num,
    hp.muted_reasons,
    blacklist.source
   FROM hivemind_app.hive_posts hp
     -- post data (6 joins)
     JOIN hivemind_app.hive_accounts_view ha_a ON ha_a.id = hp.author_id
     JOIN hivemind_app.hive_category_data hcd ON hcd.id = hp.category_id
     JOIN hivemind_app.hive_permlink_data hpd_p ON hpd_p.id = hp.permlink_id
     LEFT JOIN hivemind_app.hive_communities hc ON hp.community_id = hc.id
     LEFT JOIN hivemind_app.hive_roles hr ON hp.author_id = hr.account_id AND hp.community_id = hr.community_id
     -- parent post data 
     JOIN hivemind_app.hive_posts pp ON pp.id = hp.parent_id -- parent post (0 or 1 parent)
     JOIN hivemind_app.hive_accounts ha_pp ON ha_pp.id = pp.author_id
     JOIN hivemind_app.hive_permlink_data hpd_pp ON hpd_pp.id = pp.permlink_id
     -- root post data
     JOIN hivemind_app.hive_posts rp ON rp.id = hp.root_id -- root_post (0 or 1 root)
     JOIN hivemind_app.hive_accounts ha_rp ON ha_rp.id = rp.author_id
     JOIN hivemind_app.hive_permlink_data hpd_rp ON hpd_rp.id = rp.permlink_id
     JOIN hivemind_app.hive_category_data rcd ON rcd.id = rp.category_id
     JOIN hivemind_app.hive_post_data rpd ON rpd.id = rp.id
     LEFT JOIN hivemind_app.get_blacklisted_by_observer(_observer_id) blacklist ON (blacklist.blacklisted_id = hp.author_id) 
     -- largest joined data
     JOIN hivemind_app.hive_post_data hpd ON hpd.id = hp.id
  WHERE hp.id = _id AND hp.counter_deleted = 0;
END;
$function$ LANGUAGE plpgsql STABLE SET join_collapse_limit = 6;
--Changed join_collapse_limit from 1 to 6. Testing on a node with 5 million blocks showed a significant 
--improvement in performance for joins between hive.accounts_view and reptracker_app.account_reputations,
--reducing query time from 200ms to 12ms
