#!/bin/bash 

set -e 
set -o pipefail 

echo "Usage ./db_upgrade.sh <postgresql_url>"
rm -f ./upgrade.log

#upgrade/assert_public_schema.sql \

for sql in postgres_handle_view_changes.sql \
          upgrade/upgrade_table_schema.sql \
          utility_functions.sql \
          hive_accounts_view.sql \
          hive_accounts_info_view.sql \
          hive_posts_base_view.sql \
          hive_posts_view.sql \
          hive_votes_view.sql \
          hive_muted_accounts_view.sql \
          hive_muted_accounts_by_id_view.sql \
          hive_blacklisted_accounts_by_observer_view.sql \
          get_post_view_by_id.sql \
          hive_post_operations.sql \
          head_block_time.sql \
          update_feed_cache.sql \
          payout_stats_view.sql \
          update_hive_posts_mentions.sql \
          mutes.sql \
          bridge_get_ranked_post_type.sql \
          bridge_get_ranked_post_for_communities.sql \
          bridge_get_ranked_post_for_observer_communities.sql \
          bridge_get_ranked_post_for_tag.sql \
          bridge_get_ranked_post_for_all.sql \
          calculate_account_reputations.sql \
          update_communities_rank.sql \
          delete_hive_posts_mentions.sql \
          notifications_view.sql \
          notifications_api.sql \
          bridge_get_account_posts_by_comments.sql \
          bridge_get_account_posts_by_payout.sql \
          bridge_get_account_posts_by_posts.sql \
          bridge_get_account_posts_by_replies.sql \
          bridge_get_relationship_between_accounts.sql \
          bridge_get_post.sql \
          bridge_get_discussion.sql \
          condenser_api_post_type.sql \
          condenser_api_post_ex_type.sql \
          condenser_get_blog.sql \
          condenser_get_content.sql \
          condenser_tags.sql \
          condenser_follows.sql \
          hot_and_trends.sql \
          update_hive_posts_children_count.sql \
          update_hive_posts_api_helper.sql \
          database_api_list_comments.sql \
          database_api_list_votes.sql \
          update_posts_rshares.sql \
          update_hive_post_root_id.sql \
          condenser_get_by_account_comments.sql \
          condenser_get_by_blog_without_reblog.sql \
          bridge_get_by_feed_with_reblog.sql \
          condenser_get_by_blog.sql \
          bridge_get_account_posts_by_blog.sql \
          condenser_get_names_by_reblogged.sql \
          condenser_get_account_reputations.sql \
          update_follow_count.sql \
          bridge_get_community.sql \
          bridge_get_community_context.sql \
          bridge_list_all_subscriptions.sql \
          bridge_list_communities.sql \
          bridge_list_community_roles.sql \
          bridge_list_pop_communities.sql \
          bridge_list_subscribers.sql \
          update_follow_count.sql \
          delete_reblog_feed_cache.sql \
          follows.sql \
          is_superuser.sql \
          update_hive_blocks_consistency_flag.sql \
          community_helpers.sql \
          update_table_statistics.sql # Must be last

do
    echo Executing psql "$1" -f $sql
    time psql -a -1 -v "ON_ERROR_STOP=1" "$1"  -c '\timing' -f $sql 2>&1 | tee -a -i upgrade.log
  echo $?
done

time psql -a -v "ON_ERROR_STOP=1" "$1"  -c '\timing' -f upgrade/upgrade_runtime_migration.sql 2>&1 | tee -a -i upgrade.log

time psql -a -v "ON_ERROR_STOP=1" "$1"  -c '\timing' -f upgrade/do_conditional_vacuum.sql 2>&1 | tee -a -i upgrade.log

