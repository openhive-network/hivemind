#!/bin/bash 

set -e 

echo "Usage ./db_upgrade.sh <user-name> <db-name>"

for sql in postgres_handle_view_changes.sql \
           upgrade.sql \
           update_feed_cache.sql \
           get_account_post_replies.sql \
           payout_stats_view.sql \
           update_hive_posts_mentions.sql \
           find_tag_id.sql \
           bridge_get_ranked_post_type.sql \
           bridge_get_ranked_post_for_communities.sql \
           bridge_get_ranked_post_for_observer_communities.sql \
           bridge_get_ranked_post_for_tag.sql \
           bridge_get_ranked_post_for_all.sql \
           calculate_account_reputations.sql \
           head_block_time.sql \
           notifications_view.sql \
           notifications_api.sql \
           delete_hive_posts_mentions.sql ;
do
	echo Executing psql -U $1 -d $2 -f $sql
	psql -U $1 -d $2 -f $sql
done

