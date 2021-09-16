#!/bin/bash
#VERIFY USER and DATABASE
USER="hive"
DATABASE="hive"

echo ”accounts”
psql -U $USER -d $DATABASE -c 'select*from public_references.join_test_hive_accounts()' | tee hive_accounts_res.txt;

echo ”blocks”
psql -U $USER -d $DATABASE -c 'select*from public_references.join_test_hive_blocks()' | tee hive_blocks_res.txt;

echo ”category_data”
psql -U $USER -d $DATABASE -c 'select*from public_references.join_test_hive_category_data()' | tee hive_category_data_res.txt;

echo ”communities”
psql -U $USER -d $DATABASE -c 'select*from public_references.join_test_hive_communities()' | tee hive_communities_res.txt;

echo ”db_patch_level”
psql -U $USER -d $DATABASE -c 'select*from public_references.join_test_hive_db_patch_level()' | tee hive_db_patch_level_res.txt;

echo ”feed_cache”
psql -U $USER -d $DATABASE -c 'select*from public_references.join_test_hive_feed_cache()' | tee hive_feed_cache_res.txt;

echo ”follows”
psql -U $USER -d $DATABASE -c 'select*from public_references.join_test_hive_follows()' | tee hive_follows_res.txt;

echo ”mentions”
psql -U $USER -d $DATABASE -c 'select*from public_references.join_test_hive_mentions()' | tee hive_mentions_res.txt;

echo ”notification_cache”
psql -U $USER -d $DATABASE -c 'select*from public_references.join_test_notification_cache()' | tee hive_notification_cache_res.txt;

echo ”notifs”
psql -U $USER -d $DATABASE -c 'select*from public_references.join_test_hive_notifs()' | tee hive_notifs_res.txt;

echo ”payments”
psql -U $USER -d $DATABASE -c 'select*from public_references.join_test_hive_payments()' | tee hive_payments_res.txt;

echo ”permlink_data”
psql -U $USER -d $DATABASE -c 'select*from public_references.join_test_hive_permlink_data()' | tee hive_permlink_data_res.txt;

echo ”post_data”
psql -U $USER -d $DATABASE -c 'select*from public_references.join_test_hive_post_data()' | tee hive_post_data_res.txt;

echo ”posts”
psql -U $USER -d $DATABASE -c 'select*from public_references.join_test_hive_posts()' | tee hive_posts_res.txt;

echo ”posts_api_helper”
psql -U $USER -d $DATABASE -c 'select*from public_references.join_test_hive_posts_api_helper()' | tee hive_posts_api_helper_res.txt;

echo ”reblogs”
psql -U $USER -d $DATABASE -c 'select*from public_references.join_test_hive_reblogs()' | tee hive_reblogs_res.txt;

echo ”reputation_data”
psql -U $USER -d $DATABASE -c 'select*from public_references.join_test_hive_reputation_data()' | tee hive_reputation_data_res.txt;

echo ”roles”
psql -U $USER -d $DATABASE -c 'select*from public_references.join_test_hive_roles()' | tee hive_roles_res.txt;

echo ”state”
psql -U $USER -d $DATABASE -c 'select*from public_references.join_test_hive_state()' | tee hive_state_res.txt;

echo ”subscriptions”
psql -U $USER -d $DATABASE -c 'select*from public_references.join_test_hive_subscriptions()' | tee hive_subscriptions_res.txt;

echo ”tag_data”
psql -U $USER -d $DATABASE -c 'select*from public_references.join_test_hive_tag_data()' | tee hive_tag_data_res.txt;

echo ”votes”
psql -U $USER -d $DATABASE -c 'select*from public_references.join_test_hive_votes()' | tee hive_votes_res.txt;

