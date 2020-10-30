#!/bin/bash 

set -e 
set -o pipefail 

echo "Usage ./db_upgrade.sh <user-name> <db-name>"
rm -f ./upgrade.log

for sql in postgres_handle_view_changes.sql \
          upgrade/upgrade_table_schema.sql \
          utility_functions.sql \
          hive_accounts_view.sql \
          hive_accounts_info_view.sql \
          hive_posts_base_view.sql \
          hive_posts_view.sql \
          hive_votes_view.sql \
          hive_post_operations.sql \
          head_block_time.sql \
          update_feed_cache.sql \
          payout_stats_view.sql \
          update_hive_posts_mentions.sql \
          find_tag_id.sql \
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
          condenser_get_discussions_by_created.sql \
          condenser_get_discussions_by_blog.sql \
          hot_and_trends.sql \
          condenser_get_discussions_by_trending.sql \
          condenser_get_discussions_by_hot.sql \
          condenser_get_discussions_by_promoted.sql \
          condenser_get_post_discussions_by_payout.sql \
          condenser_get_comment_discussions_by_payout.sql \
          update_hive_posts_children_count.sql \
          update_hive_posts_api_helper.sql \
          database_api_list_comments.sql \
          database_api_list_votes.sql \
          update_posts_rshares.sql \
          update_hive_post_root_id.sql 

do
	echo Executing psql -U $1 -d $2 -f $sql
	time psql -1 -v "ON_ERROR_STOP=1" -U $1 -d $2  -c '\timing' -f $sql 2>&1 | tee -a -i upgrade.log
  echo $?
done

time psql -v "ON_ERROR_STOP=1" -U $1 -d $2  -c '\timing' -f upgrade/upgrade_runtime_migration.sql 2>&1 | tee -a -i upgrade.log
          

