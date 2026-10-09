-- PostgREST runtime SQL, in load order.
--
-- Read by hive/db/schema.py (setup_runtime_code) and
-- scripts/ci/reload-postgrest-functions.sh, which load each `\ir` target in turn;
-- `psql -f` on this file does the same. Only `\ir <path>` lines (paths relative to
-- this directory) and `--` comments belong here. A script must come after the
-- scripts whose objects it references at creation time.
--
-- The list lives in the PostgREST tree, not in schema.py, so adding an endpoint
-- stays a PostgREST-only change that CI reloads on cached data instead of re-syncing.
--
-- utilities/preprocess_search_query.sql is not listed: it needs the admin role and
-- is installed by setup() in schema.py.

\ir home.sql
\ir utilities/exceptions.sql
\ir utilities/validate_json_arguments.sql
\ir utilities/api_limits.sql
\ir utilities/parse_argument_from_json.sql
\ir utilities/valid_account.sql
\ir utilities/find_account_id.sql
\ir condenser_api/condenser_api_get_follow_count.sql
\ir utilities/find_comment_id.sql
\ir utilities/valid_permlink.sql
\ir condenser_api/condenser_api_get_reblogged_by.sql
\ir utilities/valid_number.sql
\ir utilities/valid_tag.sql
\ir utilities/find_category_id.sql
\ir condenser_api/condenser_api_get_trending_tags.sql
\ir condenser_api/condenser_api_get_account_reputations.sql
\ir utilities/check_community.sql
\ir utilities/valid_community.sql
\ir utilities/valid_limit.sql
\ir utilities/json_date.sql
\ir utilities/community.sql
\ir bridge_api/bridge_api_get_community.sql
\ir bridge_api/bridge_api_get_community_context.sql
\ir utilities/dispatch.sql
\ir utilities/get_api_method.sql
\ir utilities/valid_offset.sql
\ir utilities/list_votes.sql
\ir utilities/assets_operations.sql
\ir utilities/create_condenser_post_object.sql
\ir condenser_api/condenser_api_get_blog.sql
\ir condenser_api/condenser_api_get_content.sql
\ir database_api/database_api_find_votes.sql
\ir database_api/database_api_list_votes.sql
\ir condenser_api/condenser_api_get_active_votes.sql
\ir utilities/rep_log10.sql
\ir utilities/muted_reasons_operations.sql
\ir utilities/create_bridge_post_object.sql
\ir bridge_api/bridge_api_get_post.sql
\ir bridge_api/bridge_api_get_payout_stats.sql
\ir hive_api/hive_api_get_info.sql
\ir hive_api/hive_api_db_head_state.sql
\ir utilities/get_account_posts.sql
\ir utilities/get_account_posts_by_tag.sql
\ir bridge_api/bridge_api_get_account_posts.sql
\ir bridge_api/bridge_api_get_account_posts_by_tag.sql
\ir bridge_api/bridge_api_get_relationship_between_accounts.sql
\ir bridge_api/bridge_api_unread_notifications.sql
\ir utilities/find_tag_id.sql
\ir utilities/get_ranked_posts.sql
\ir utilities/get_reblogged_posts.sql
\ir bridge_api/bridge_api_get_ranked_posts.sql
\ir condenser_api/condenser_api_get_discussions_by_blog_or_feed.sql
\ir condenser_api/condenser_api_get_discussions_by_comments.sql
\ir condenser_api/condenser_api_get_replies_by_last_update.sql
\ir condenser_api/condenser_api_get_discussion_by_author_before_date.sql
\ir condenser_api/condenser_api_get_discussion_by.sql
\ir utilities/notifications.sql
\ir bridge_api/bridge_api_account_notifications.sql
\ir bridge_api/bridge_api_post_notifications.sql
\ir utilities/create_database_post_object.sql
\ir database_api/database_api_find_comments.sql
\ir utilities/valid_date.sql
\ir bridge_api/bridge_api_list_subscribers.sql
\ir bridge_api/bridge_api_get_trending_topics.sql
\ir bridge_api/bridge_api_list_communities.sql
\ir bridge_api/bridge_api_get_discussion.sql
\ir bridge_api/bridge_api_list_votes.sql
\ir bridge_api/bridge_api_get_post_header.sql
\ir utilities/get_profiles.sql
\ir utilities/get_muted_accounts_list.sql
\ir bridge_api/bridge_api_get_profile.sql
\ir bridge_api/bridge_api_does_user_follow_any_lists.sql
\ir utilities/extract_profile_metadata.sql
\ir bridge_api/bridge_api_get_follow_list.sql
\ir utilities/get_role_name.sql
\ir utilities/find_community_id.sql
\ir bridge_api/bridge_api_list_community_roles.sql
\ir bridge_api/bridge_api_list_all_subscriptions.sql
\ir bridge_api/bridge_api_list_pop_communities.sql
\ir condenser_api/extract_parameters_for_get_following_and_followers.sql
\ir condenser_api/condenser_api_get_followers.sql
\ir condenser_api/condenser_api_get_following.sql
\ir utilities/find_subscription_id.sql
\ir bridge_api/bridge_api_get_profiles.sql
\ir utilities/valid_accounts.sql
\ir search-api/find_text.sql
\ir ../endpoints/endpoint_schema.sql
\ir ../endpoints/types/operation.sql
\ir ../endpoints/accounts/get_ops_by_account.sql
\ir ../endpoints/accounts/get_account_pending_author_rewards.sql
\ir ../endpoints/accounts/get_account_pending_curation_rewards.sql
\ir ../endpoints/blog/get_reblogs.sql
\ir ../endpoints/other/get_sync_status.sql
