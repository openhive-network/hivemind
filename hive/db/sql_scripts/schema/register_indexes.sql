-- Register all disableable indexes with HAF's index management framework.
-- These indexes are dropped during massive sync and restored afterward.
-- Uses SECURITY DEFINER app_register_index_dependency so app roles can register indexes.

-- hive_feed_cache indexes
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_feed_cache_block_num_idx ON hivemind_app.hive_feed_cache (block_num)');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_feed_cache_created_at_idx ON hivemind_app.hive_feed_cache (created_at)');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_feed_cache_post_id_idx ON hivemind_app.hive_feed_cache (post_id)');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_feed_cache_account_id_created_at_post_id_idx ON hivemind_app.hive_feed_cache (account_id, created_at DESC, post_id DESC)');

-- hive_posts indexes
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_posts_parent_id_id_idx ON hivemind_app.hive_posts (parent_id, id DESC) INCLUDE (author_id) WHERE counter_deleted = 0');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_posts_depth_idx ON hivemind_app.hive_posts (depth)');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_posts_root_id_id_idx ON hivemind_app.hive_posts (root_id, id)');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_posts_community_id_id_idx ON hivemind_app.hive_posts (community_id, id DESC) WHERE counter_deleted = 0');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_posts_community_id_is_pinned_idx ON hivemind_app.hive_posts (community_id) INCLUDE (id) WHERE is_pinned AND counter_deleted = 0');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_posts_community_id_not_is_pinned_idx ON hivemind_app.hive_posts (community_id, id DESC) WHERE NOT is_pinned AND depth = 0 AND counter_deleted = 0');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_posts_community_id_not_is_paidout_idx ON hivemind_app.hive_posts (community_id) INCLUDE (id) WHERE NOT is_paidout AND depth = 0 AND counter_deleted = 0');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_posts_payout_at_idx ON hivemind_app.hive_posts (payout_at)');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_posts_sc_trend_id_idx ON hivemind_app.hive_posts (sc_trend, id) WHERE NOT is_paidout AND counter_deleted = 0 AND depth = 0');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_posts_sc_hot_id_idx ON hivemind_app.hive_posts (sc_hot, id) WHERE NOT is_paidout AND counter_deleted = 0 AND depth = 0');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_posts_block_num_created_idx ON hivemind_app.hive_posts (block_num_created)');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_posts_payout_plus_pending_payout_id_idx ON hivemind_app.hive_posts ((payout+pending_payout), id) WHERE NOT is_paidout AND counter_deleted = 0');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_posts_category_id_payout_plus_pending_payout_depth_idx ON hivemind_app.hive_posts (category_id, (payout+pending_payout), depth) WHERE NOT is_paidout AND counter_deleted = 0');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_posts_author_id_created_at_id_idx ON hivemind_app.hive_posts (author_id DESC, created_at DESC, id)');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_posts_author_id_id_idx ON hivemind_app.hive_posts (author_id, id DESC) WHERE counter_deleted = 0');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_posts_block_num_idx ON hivemind_app.hive_posts (block_num)');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_posts_author_id_id_depth0_idx ON hivemind_app.hive_posts (author_id, id DESC) WHERE depth = 0 AND counter_deleted = 0');

-- hive_votes indexes
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_votes_voter_id_last_update_idx ON hivemind_app.hive_votes (voter_id, last_update)');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_votes_block_num_idx ON hivemind_app.hive_votes (block_num)');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_votes_post_id_voter_id_idx ON hivemind_app.hive_votes (post_id, voter_id)');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_votes_post_id_block_num_rshares_vote_is_effective_idx ON hivemind_app.hive_votes (post_id, block_num, rshares, is_effective)');

-- hive_subscriptions indexes
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_subscriptions_block_num_idx ON hivemind_app.hive_subscriptions (block_num)');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_subscriptions_community_idx ON hivemind_app.hive_subscriptions (community_id)');

-- hive_communities indexes
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_communities_block_num_idx ON hivemind_app.hive_communities (block_num)');

-- hive_notification_cache indexes
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_notification_cache_block_num_idx ON hivemind_app.hive_notification_cache (block_num)');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_notification_cache_dst_score_idx ON hivemind_app.hive_notification_cache (dst, score) WHERE dst IS NOT NULL');

-- follows/muted/blacklisted indexes
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS follows_following_idx ON hivemind_app.follows (following)');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS muted_following_idx ON hivemind_app.muted (following)');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS blacklisted_following_idx ON hivemind_app.blacklisted (following)');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS follow_muted_following_idx ON hivemind_app.follow_muted (following)');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS follow_blacklisted_following_idx ON hivemind_app.follow_blacklisted (following)');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS follows_block_num_idx ON hivemind_app.follows (block_num)');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS muted_block_num_idx ON hivemind_app.muted (block_num)');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS blacklisted_block_num_idx ON hivemind_app.blacklisted (block_num)');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS follow_muted_block_num_idx ON hivemind_app.follow_muted (block_num)');
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS follow_blacklisted_block_num_idx ON hivemind_app.follow_blacklisted (block_num)');

-- NOTE: hive_post_data BM25 index is NOT registered here. pg_search leaves internal
-- metadata (MetaPage) that prevents UNLOGGED conversion even after the index is dropped.
-- The BM25 index is created directly during the fills phase after massive sync completes.

-- hive_accounts indexes
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS hive_accounts_haf_id_idx ON hivemind_app.hive_accounts (haf_id)');

-- reputation tracker index (managed alongside hivemind's indexes)
SELECT hive.app_register_index_dependency('hivemind_app', 'CREATE INDEX IF NOT EXISTS idx_reputation_on_account_reputations ON reptracker_app.account_reputations (reputation)');
