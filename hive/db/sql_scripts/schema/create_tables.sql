-- Hivemind application tables, indexes, and unique constraints.
-- Translated from SQLAlchemy metadata definitions.

-- hive_accounts
CREATE TABLE IF NOT EXISTS hivemind_app.hive_accounts (
    id SERIAL PRIMARY KEY,
    haf_id INTEGER,
    name VARCHAR(16) COLLATE "C" NOT NULL,
    created_at TIMESTAMP NOT NULL,
    followers INTEGER NOT NULL DEFAULT 0,
    following INTEGER NOT NULL DEFAULT 0,
    rank INTEGER NOT NULL DEFAULT 0,
    lastread_at TIMESTAMP NOT NULL DEFAULT '1970-01-01 00:00:00',
    posting_json_metadata TEXT,
    json_metadata TEXT,
    CONSTRAINT hive_accounts_ux1 UNIQUE (name)
);
CREATE INDEX IF NOT EXISTS hive_accounts_haf_id_idx ON hivemind_app.hive_accounts (haf_id);

-- hive_posts
CREATE TABLE IF NOT EXISTS hivemind_app.hive_posts (
    id SERIAL PRIMARY KEY,
    root_id INTEGER NOT NULL,
    parent_id INTEGER NOT NULL,
    author_id INTEGER NOT NULL,
    permlink_id INTEGER NOT NULL,
    category_id INTEGER NOT NULL,
    community_id INTEGER,
    created_at TIMESTAMP NOT NULL,
    depth SMALLINT NOT NULL,
    counter_deleted INTEGER NOT NULL DEFAULT 0,
    is_pinned BOOLEAN NOT NULL DEFAULT FALSE,
    is_muted BOOLEAN NOT NULL DEFAULT FALSE,
    muted_reasons INTEGER NOT NULL DEFAULT 0,
    is_valid BOOLEAN NOT NULL DEFAULT TRUE,
    children INTEGER NOT NULL DEFAULT 0,
    payout DECIMAL(10,3) NOT NULL DEFAULT 0,
    pending_payout DECIMAL(10,3) NOT NULL DEFAULT 0,
    payout_at TIMESTAMP NOT NULL DEFAULT '1970-01-01',
    last_payout_at TIMESTAMP NOT NULL DEFAULT '1970-01-01',
    updated_at TIMESTAMP NOT NULL DEFAULT '1970-01-01',
    is_paidout BOOLEAN NOT NULL DEFAULT FALSE,
    is_nsfw BOOLEAN NOT NULL DEFAULT FALSE,
    is_declined BOOLEAN NOT NULL DEFAULT FALSE,
    is_full_power BOOLEAN NOT NULL DEFAULT FALSE,
    is_hidden BOOLEAN NOT NULL DEFAULT FALSE,
    sc_trend REAL NOT NULL DEFAULT 0,
    sc_hot REAL NOT NULL DEFAULT 0,
    total_payout_value VARCHAR(30) NOT NULL DEFAULT '0.000 HBD',
    author_rewards BIGINT NOT NULL DEFAULT 0,
    author_rewards_hive BIGINT NOT NULL DEFAULT 0,
    author_rewards_hbd BIGINT NOT NULL DEFAULT 0,
    author_rewards_vests BIGINT NOT NULL DEFAULT 0,
    abs_rshares NUMERIC NOT NULL DEFAULT 0,
    vote_rshares NUMERIC NOT NULL DEFAULT 0,
    total_vote_weight NUMERIC NOT NULL DEFAULT 0,
    total_votes BIGINT NOT NULL DEFAULT 0,
    net_votes BIGINT NOT NULL DEFAULT 0,
    active TIMESTAMP NOT NULL DEFAULT '1970-01-01 00:00:00',
    cashout_time TIMESTAMP NOT NULL DEFAULT '1970-01-01 00:00:00',
    percent_hbd INTEGER NOT NULL DEFAULT 10000,
    curator_payout_value VARCHAR(30) NOT NULL DEFAULT '0.000 HBD',
    max_accepted_payout VARCHAR(30) NOT NULL DEFAULT '1000000.000 HBD',
    allow_votes BOOLEAN NOT NULL DEFAULT TRUE,
    allow_curation_rewards BOOLEAN NOT NULL DEFAULT TRUE,
    beneficiaries JSON NOT NULL DEFAULT '[]',
    block_num INTEGER NOT NULL,
    block_num_created INTEGER NOT NULL,
    last_payout_block INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT hive_posts_ux1 UNIQUE (author_id, permlink_id, counter_deleted)
);
CREATE INDEX IF NOT EXISTS hive_posts_depth_idx ON hivemind_app.hive_posts (depth);
CREATE INDEX IF NOT EXISTS hive_posts_root_id_id_idx ON hivemind_app.hive_posts (root_id, id);
CREATE INDEX IF NOT EXISTS hive_posts_parent_id_id_idx ON hivemind_app.hive_posts (parent_id, id DESC) INCLUDE (author_id) WHERE counter_deleted = 0;
CREATE INDEX IF NOT EXISTS hive_posts_community_id_id_idx ON hivemind_app.hive_posts (community_id, id DESC) WHERE counter_deleted = 0;
CREATE INDEX IF NOT EXISTS hive_posts_community_id_is_pinned_idx ON hivemind_app.hive_posts (community_id) INCLUDE (id) WHERE is_pinned AND counter_deleted = 0;
CREATE INDEX IF NOT EXISTS hive_posts_community_id_not_is_pinned_idx ON hivemind_app.hive_posts (community_id, id DESC) WHERE NOT is_pinned AND depth = 0 AND counter_deleted = 0;
CREATE INDEX IF NOT EXISTS hive_posts_community_id_not_is_paidout_idx ON hivemind_app.hive_posts (community_id) INCLUDE (id) WHERE NOT is_paidout AND depth = 0 AND counter_deleted = 0;
CREATE INDEX IF NOT EXISTS hive_posts_payout_at_idx ON hivemind_app.hive_posts (payout_at);
CREATE INDEX IF NOT EXISTS hive_posts_sc_trend_id_idx ON hivemind_app.hive_posts (sc_trend, id) WHERE NOT is_paidout AND counter_deleted = 0 AND depth = 0;
CREATE INDEX IF NOT EXISTS hive_posts_sc_hot_id_idx ON hivemind_app.hive_posts (sc_hot, id) WHERE NOT is_paidout AND counter_deleted = 0 AND depth = 0;
CREATE INDEX IF NOT EXISTS hive_posts_author_id_created_at_id_idx ON hivemind_app.hive_posts (author_id DESC, created_at DESC, id);
CREATE INDEX IF NOT EXISTS hive_posts_author_id_id_idx ON hivemind_app.hive_posts (author_id, id DESC) WHERE counter_deleted = 0;
CREATE INDEX IF NOT EXISTS hive_posts_author_id_id_depth0_idx ON hivemind_app.hive_posts (author_id, id DESC) WHERE depth = 0 AND counter_deleted = 0;
CREATE INDEX IF NOT EXISTS hive_posts_block_num_idx ON hivemind_app.hive_posts (block_num);
CREATE INDEX IF NOT EXISTS hive_posts_block_num_created_idx ON hivemind_app.hive_posts (block_num_created);
CREATE INDEX IF NOT EXISTS hive_posts_payout_plus_pending_payout_id_idx ON hivemind_app.hive_posts ((payout+pending_payout), id) WHERE NOT is_paidout AND counter_deleted = 0;
CREATE INDEX IF NOT EXISTS hive_posts_category_id_payout_plus_pending_payout_depth_idx ON hivemind_app.hive_posts (category_id, (payout+pending_payout), depth) WHERE NOT is_paidout AND counter_deleted = 0;

-- hive_post_data
CREATE TABLE IF NOT EXISTS hivemind_app.hive_post_data (
    id INTEGER PRIMARY KEY,
    title VARCHAR(512) NOT NULL DEFAULT '',
    body TEXT NOT NULL DEFAULT '',
    json TEXT NOT NULL DEFAULT ''
);
-- BM25 index for full-text search is created conditionally in Python (requires pg_search extension)

-- hive_permlink_data
CREATE TABLE IF NOT EXISTS hivemind_app.hive_permlink_data (
    id SERIAL PRIMARY KEY,
    permlink VARCHAR(255) COLLATE "C" NOT NULL,
    CONSTRAINT hive_permlink_data_permlink UNIQUE (permlink)
);

-- hive_category_data
CREATE TABLE IF NOT EXISTS hivemind_app.hive_category_data (
    id SERIAL PRIMARY KEY,
    category VARCHAR(255) COLLATE "C" NOT NULL,
    CONSTRAINT hive_category_data_category UNIQUE (category)
);

-- hive_votes
CREATE TABLE IF NOT EXISTS hivemind_app.hive_votes (
    id BIGSERIAL PRIMARY KEY,
    post_id INTEGER NOT NULL,
    voter_id INTEGER NOT NULL,
    author_id INTEGER NOT NULL,
    permlink_id INTEGER NOT NULL,
    weight NUMERIC NOT NULL DEFAULT 0,
    rshares BIGINT NOT NULL DEFAULT 0,
    vote_percent INTEGER NOT NULL DEFAULT 0,
    last_update TIMESTAMP NOT NULL DEFAULT '1970-01-01 00:00:00',
    num_changes INTEGER NOT NULL DEFAULT 0,
    block_num INTEGER NOT NULL,
    is_effective BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT hive_votes_voter_id_author_id_permlink_id_uk UNIQUE (voter_id, author_id, permlink_id)
);
CREATE INDEX IF NOT EXISTS hive_votes_voter_id_last_update_idx ON hivemind_app.hive_votes (voter_id, last_update);
CREATE INDEX IF NOT EXISTS hive_votes_post_id_voter_id_idx ON hivemind_app.hive_votes (post_id, voter_id);
CREATE INDEX IF NOT EXISTS hive_votes_block_num_idx ON hivemind_app.hive_votes (block_num);
CREATE INDEX IF NOT EXISTS hive_votes_post_id_block_num_rshares_vote_is_effective_idx ON hivemind_app.hive_votes (post_id, block_num, rshares, is_effective);

-- hive_post_tags
CREATE TABLE IF NOT EXISTS hivemind_app.hive_post_tags (
    post_id INTEGER NOT NULL,
    tag_id INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS hive_post_tags_idx ON hivemind_app.hive_post_tags USING btree (post_id, tag_id);

-- hive_tag_data
CREATE TABLE IF NOT EXISTS hivemind_app.hive_tag_data (
    id SERIAL PRIMARY KEY,
    tag VARCHAR(64) COLLATE "C" NOT NULL DEFAULT '',
    CONSTRAINT hive_tag_data_ux1 UNIQUE (tag)
);

-- hive_reblogs
CREATE TABLE IF NOT EXISTS hivemind_app.hive_reblogs (
    id SERIAL PRIMARY KEY,
    blogger_id INTEGER NOT NULL,
    post_id INTEGER NOT NULL,
    created_at TIMESTAMP NOT NULL,
    block_num INTEGER NOT NULL,
    CONSTRAINT hive_reblogs_ux1 UNIQUE (blogger_id, post_id)
);
CREATE INDEX IF NOT EXISTS hive_reblogs_post_id ON hivemind_app.hive_reblogs (post_id);
CREATE INDEX IF NOT EXISTS hive_reblogs_block_num_idx ON hivemind_app.hive_reblogs (block_num);

-- hive_feed_cache
CREATE TABLE IF NOT EXISTS hivemind_app.hive_feed_cache (
    post_id INTEGER NOT NULL,
    account_id INTEGER NOT NULL,
    created_at TIMESTAMP NOT NULL,
    block_num INTEGER NOT NULL,
    CONSTRAINT hive_feed_cache_pk PRIMARY KEY (account_id, post_id)
);
CREATE INDEX IF NOT EXISTS hive_feed_cache_block_num_idx ON hivemind_app.hive_feed_cache (block_num);
CREATE INDEX IF NOT EXISTS hive_feed_cache_created_at_idx ON hivemind_app.hive_feed_cache (created_at);
CREATE INDEX IF NOT EXISTS hive_feed_cache_post_id_idx ON hivemind_app.hive_feed_cache (post_id);
CREATE INDEX IF NOT EXISTS hive_feed_cache_account_id_created_at_post_id_idx ON hivemind_app.hive_feed_cache (account_id, created_at DESC, post_id DESC);

-- hive_state
CREATE TABLE IF NOT EXISTS hivemind_app.hive_state (
    last_completed_block_num INTEGER NOT NULL,
    db_version INTEGER NOT NULL,
    hivemind_version TEXT NOT NULL DEFAULT '',
    hivemind_git_date TIMESTAMP NOT NULL DEFAULT now(),
    hivemind_git_rev TEXT NOT NULL DEFAULT ''
);

-- hive_mentions
CREATE TABLE IF NOT EXISTS hivemind_app.hive_mentions (
    id SERIAL PRIMARY KEY,
    post_id INTEGER NOT NULL,
    account_id INTEGER NOT NULL,
    block_num INTEGER NOT NULL,
    CONSTRAINT hive_mentions_ux1 UNIQUE (post_id, account_id, block_num)
);

-- hive_communities
CREATE TABLE IF NOT EXISTS hivemind_app.hive_communities (
    id INTEGER PRIMARY KEY,
    type_id SMALLINT NOT NULL,
    lang CHAR(2) NOT NULL DEFAULT 'en',
    name VARCHAR(16) COLLATE "C" NOT NULL,
    title VARCHAR(32) NOT NULL DEFAULT '',
    created_at TIMESTAMP NOT NULL,
    sum_pending INTEGER NOT NULL DEFAULT 0,
    num_pending INTEGER NOT NULL DEFAULT 0,
    num_authors INTEGER NOT NULL DEFAULT 0,
    rank INTEGER NOT NULL DEFAULT 0,
    subscribers INTEGER NOT NULL DEFAULT 0,
    is_nsfw BOOLEAN NOT NULL DEFAULT FALSE,
    about VARCHAR(120) NOT NULL DEFAULT '',
    primary_tag VARCHAR(32) NOT NULL DEFAULT '',
    category VARCHAR(32) NOT NULL DEFAULT '',
    description VARCHAR(5000) NOT NULL DEFAULT '',
    flag_text VARCHAR(5000) NOT NULL DEFAULT '',
    settings JSONB NOT NULL DEFAULT '{}',
    block_num INTEGER NOT NULL,
    CONSTRAINT hive_communities_ux1 UNIQUE (name)
);
CREATE INDEX IF NOT EXISTS hive_communities_ix1 ON hivemind_app.hive_communities (rank, id);
CREATE INDEX IF NOT EXISTS hive_communities_block_num_idx ON hivemind_app.hive_communities (block_num);

-- hive_roles
CREATE TABLE IF NOT EXISTS hivemind_app.hive_roles (
    account_id INTEGER NOT NULL,
    community_id INTEGER NOT NULL,
    created_at TIMESTAMP NOT NULL,
    role_id SMALLINT NOT NULL DEFAULT 0,
    title VARCHAR(140) NOT NULL DEFAULT '',
    CONSTRAINT hive_roles_pk PRIMARY KEY (account_id, community_id)
);
CREATE INDEX IF NOT EXISTS hive_roles_ix1 ON hivemind_app.hive_roles (community_id, account_id, role_id);

-- hive_subscriptions
CREATE TABLE IF NOT EXISTS hivemind_app.hive_subscriptions (
    id SERIAL PRIMARY KEY,
    account_id INTEGER NOT NULL,
    community_id INTEGER NOT NULL,
    created_at TIMESTAMP NOT NULL,
    block_num INTEGER NOT NULL,
    CONSTRAINT hive_subscriptions_ux1 UNIQUE (account_id, community_id)
);
CREATE INDEX IF NOT EXISTS hive_subscriptions_community_idx ON hivemind_app.hive_subscriptions (community_id);
CREATE INDEX IF NOT EXISTS hive_subscriptions_block_num_idx ON hivemind_app.hive_subscriptions (block_num);

-- hive_notification_cache
CREATE TABLE IF NOT EXISTS hivemind_app.hive_notification_cache (
    id BIGINT PRIMARY KEY,
    block_num INTEGER NOT NULL,
    type_id INTEGER NOT NULL,
    dst INTEGER,
    src INTEGER,
    dst_post_id INTEGER,
    post_id INTEGER,
    created_at TIMESTAMP NOT NULL,
    score INTEGER NOT NULL,
    community_title VARCHAR(32),
    community VARCHAR(16),
    payload VARCHAR
);
CREATE INDEX IF NOT EXISTS hive_notification_cache_block_num_idx ON hivemind_app.hive_notification_cache (block_num);
CREATE UNIQUE INDEX IF NOT EXISTS hive_notification_cache_src_dst_post_id ON hivemind_app.hive_notification_cache (src, dst, type_id, post_id, block_num);
CREATE INDEX IF NOT EXISTS hive_notification_cache_dst_score_idx ON hivemind_app.hive_notification_cache (dst, score) WHERE dst IS NOT NULL;

-- follows
CREATE TABLE IF NOT EXISTS hivemind_app.follows (
    follower INTEGER NOT NULL,
    following INTEGER NOT NULL,
    block_num INTEGER NOT NULL,
    PRIMARY KEY (follower, following)
);
CREATE INDEX IF NOT EXISTS follows_following_idx ON hivemind_app.follows (following);
CREATE INDEX IF NOT EXISTS follows_block_num_idx ON hivemind_app.follows (block_num);

-- muted
CREATE TABLE IF NOT EXISTS hivemind_app.muted (
    follower INTEGER NOT NULL,
    following INTEGER NOT NULL,
    block_num INTEGER NOT NULL,
    PRIMARY KEY (follower, following)
);
CREATE INDEX IF NOT EXISTS muted_following_idx ON hivemind_app.muted (following);
CREATE INDEX IF NOT EXISTS muted_block_num_idx ON hivemind_app.muted (block_num);

-- blacklisted
CREATE TABLE IF NOT EXISTS hivemind_app.blacklisted (
    follower INTEGER NOT NULL,
    following INTEGER NOT NULL,
    block_num INTEGER NOT NULL,
    PRIMARY KEY (follower, following)
);
CREATE INDEX IF NOT EXISTS blacklisted_following_idx ON hivemind_app.blacklisted (following);
CREATE INDEX IF NOT EXISTS blacklisted_block_num_idx ON hivemind_app.blacklisted (block_num);

-- follow_muted
CREATE TABLE IF NOT EXISTS hivemind_app.follow_muted (
    follower INTEGER NOT NULL,
    following INTEGER NOT NULL,
    block_num INTEGER NOT NULL,
    PRIMARY KEY (follower, following)
);
CREATE INDEX IF NOT EXISTS follow_muted_following_idx ON hivemind_app.follow_muted (following);
CREATE INDEX IF NOT EXISTS follow_muted_block_num_idx ON hivemind_app.follow_muted (block_num);

-- follow_blacklisted
CREATE TABLE IF NOT EXISTS hivemind_app.follow_blacklisted (
    follower INTEGER NOT NULL,
    following INTEGER NOT NULL,
    block_num INTEGER NOT NULL,
    PRIMARY KEY (follower, following)
);
CREATE INDEX IF NOT EXISTS follow_blacklisted_following_idx ON hivemind_app.follow_blacklisted (following);
CREATE INDEX IF NOT EXISTS follow_blacklisted_block_num_idx ON hivemind_app.follow_blacklisted (block_num);
