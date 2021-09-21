#!/bin/bash
#VERIFY USER and DATABASE

#  -1  ---- test table have a missing raw
#  +1  ---- test table have a additional raw
#   2  ---- raw in test table have incorrect data

USER="hive"
DATABASE="hive"

#DROP RESOULTS TABLES

psql -U $USER -d $DATABASE -c 'drop table public.accounts_resoults';
psql -U $USER -d $DATABASE -c 'drop table public.test_blocks_resoults';
psql -U $USER -d $DATABASE -c 'drop table public.test_category_resoults';
psql -U $USER -d $DATABASE -c 'drop table public.test_communities_resoults';
psql -U $USER -d $DATABASE -c 'drop table public.test_db_patch_level_resoults';
psql -U $USER -d $DATABASE -c 'drop table public.test_feed_cache_resoults';
psql -U $USER -d $DATABASE -c 'drop table public.test_follows_resoults';
psql -U $USER -d $DATABASE -c 'drop table public.test_mentions_resoults';
psql -U $USER -d $DATABASE -c 'drop table public.test_notification_cache_resoults';
psql -U $USER -d $DATABASE -c 'drop table public.test_notifs_resoults';
psql -U $USER -d $DATABASE -c 'drop table public.test_payments_resoults';
psql -U $USER -d $DATABASE -c 'drop table public.test_permlink_data_resoults';
psql -U $USER -d $DATABASE -c 'drop table public.test_post_data_resoults';
psql -U $USER -d $DATABASE -c 'drop table public.test_posts_resoults';
psql -U $USER -d $DATABASE -c 'drop table public.test_posts_api_helper_resoults';
psql -U $USER -d $DATABASE -c 'drop table public.test_reblogs_resoults';
psql -U $USER -d $DATABASE -c 'drop table public.test_reputation_data_resoults';
psql -U $USER -d $DATABASE -c 'drop table public.test_roles_resoults';
psql -U $USER -d $DATABASE -c 'drop table public.test_state_resoults';
psql -U $USER -d $DATABASE -c 'drop table public.test_subscriptions_resoults';
psql -U $USER -d $DATABASE -c 'drop table public.test_tag_data_resoults';
psql -U $USER -d $DATABASE -c 'drop table public.test_votes_resoults';


#SAVE A RESOULTS TO TABLES
echo ”accounts”
psql -U $USER -d $DATABASE -c 'create table public.accounts_resoults as( select*from public_references.join_test_hive_accounts())';

echo ”blocks”
psql -U $USER -d $DATABASE -c 'create table public.test_blocks_resoults as( select*from public_references.join_test_hive_blocks())';

echo ”category_data”
psql -U $USER -d $DATABASE -c 'create table public.test_category_resoults as( select*from public_references.join_test_hive_category_data())';

echo ”communities”
psql -U $USER -d $DATABASE -c 'create table public.test_communities_resoults as( select*from public_references.join_test_hive_communities())';

echo ”db_patch_level”
psql -U $USER -d $DATABASE -c 'create table public.test_db_patch_level_resoults as( select*from public_references.join_test_hive_db_patch_level())';

echo ”feed_cache”
psql -U $USER -d $DATABASE -c 'create table public.test_feed_cache_resoults as( select*from public_references.join_test_hive_feed_cache())';

echo ”follows”
psql -U $USER -d $DATABASE -c 'create table public.test_follows_resoults as( select*from public_references.join_test_hive_follows())';

echo ”mentions”
psql -U $USER -d $DATABASE -c 'create table public.test_mentions_resoults as( select*from public_references.join_test_hive_mentions())';

echo ”notification_cache”
psql -U $USER -d $DATABASE -c 'create table public.test_notification_cache_resoults as( select*from public_references.join_test_notification_cache())';

echo ”notifs”
psql -U $USER -d $DATABASE -c 'create table public.test_notifs_resoults as( select*from public_references.join_test_hive_notifs())';

echo ”payments”
psql -U $USER -d $DATABASE -c 'create table public.test_payments_resoults as( select*from public_references.join_test_hive_payments())';

echo ”permlink_data”
psql -U $USER -d $DATABASE -c 'create table public.test_permlink_data_resoults as( select*from public_references.join_test_hive_permlink_data())';

echo ”post_data”
psql -U $USER -d $DATABASE -c 'create table public.test_post_data_resoults as( select*from public_references.join_test_hive_post_data())';

echo ”posts”
psql -U $USER -d $DATABASE -c 'create table public.test_posts_resoults as( select*from public_references.join_test_hive_posts())';

echo ”posts_api_helper”
psql -U $USER -d $DATABASE -c 'create table public.test_posts_api_helper_resoults as( select*from public_references.join_test_hive_posts_api_helper())';

echo ”reblogs”
psql -U $USER -d $DATABASE -c 'create table public.test_reblogs_resoults as( select*from public_references.join_test_hive_reblogs())';

echo ”reputation_data”
psql -U $USER -d $DATABASE -c 'create table public.test_reputation_data_resoults as( select*from public_references.join_test_hive_reputation_data())';

echo ”roles”
psql -U $USER -d $DATABASE -c 'create table public.test_roles_resoults as( select*from public_references.join_test_hive_roles())';

echo ”state”
psql -U $USER -d $DATABASE -c 'create table public.test_state_resoults as( select*from public_references.join_test_hive_state())';

echo ”subscriptions”
psql -U $USER -d $DATABASE -c 'create table public.test_subscriptions_resoults as( select*from public_references.join_test_hive_subscriptions())';

echo ”tag_data”
psql -U $USER -d $DATABASE -c 'create table public.test_tag_data_resoults as( select*from public_references.join_test_hive_tag_data())';

echo ”votes”
psql -U $USER -d $DATABASE -c 'create table public.test_votes_resoults as( select*from public_references.join_test_hive_votes())';

