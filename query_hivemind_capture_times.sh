#!/bin/bash

HOST=127.0.0.1:8085

echo "condenser_api.get_content" >> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":1, "method":"condenser_api.get_content", "params":{"author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":2, "method":"condenser_api.get_content", "params":{"author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":3, "method":"condenser_api.get_content", "params":{"author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance"}}' $HOST ; } 2>> query_times.log
echo "" >> query_times.log

echo "condenser_api.get_content_replies" >> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":4, "method":"condenser_api.get_content_replies", "params":{"author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":5, "method":"condenser_api.get_content_replies", "params":{"author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":6, "method":"condenser_api.get_content_replies", "params":{"author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance"}}' $HOST ; } 2>> query_times.log
echo "" >> query_times.log

echo "condenser_api.get_discussions_by_trending" >> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"condenser_api.get_discussions_by_trending", "params":{}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":8, "method":"condenser_api.get_discussions_by_trending", "params":{}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":9, "method":"condenser_api.get_discussions_by_trending", "params":{}}' $HOST ; } 2>> query_times.log
echo "" >> query_times.log

echo "condenser_api.get_discussions_by_hot" >> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"condenser_api.get_discussions_by_hot", "params":{}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"condenser_api.get_discussions_by_hot", "params":{}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"condenser_api.get_discussions_by_hot", "params":{}}' $HOST ; } 2>> query_times.log
echo "" >> query_times.log

echo "condenser_api.get_discussions_by_promoted" >> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"condenser_api.get_discussions_by_promoted", "params":{}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"condenser_api.get_discussions_by_promoted", "params":{}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"condenser_api.get_discussions_by_promoted", "params":{}}' $HOST ; } 2>> query_times.log
echo "" >> query_times.log

echo "condenser_api.get_discussions_by_created" >> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"condenser_api.get_discussions_by_created", "params":{}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"condenser_api.get_discussions_by_created", "params":{}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"condenser_api.get_discussions_by_created", "params":{}}' $HOST ; } 2>> query_times.log
echo "" >> query_times.log

echo "condenser_api.get_discussions_by_blog" >> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"condenser_api.get_discussions_by_blog", "params":{"tag":"blocktrades"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"condenser_api.get_discussions_by_blog", "params":{"tag":"blocktrades"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"condenser_api.get_discussions_by_blog", "params":{"tag":"blocktrades"}}' $HOST ; } 2>> query_times.log
echo "" >> query_times.log

echo "condenser_api.get_discussions_by_feed" >> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"condenser_api.get_discussions_by_feed", "params":{"tag":"blocktrades"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"condenser_api.get_discussions_by_feed", "params":{"tag":"blocktrades"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"condenser_api.get_discussions_by_feed", "params":{"tag":"blocktrades"}}' $HOST ; } 2>> query_times.log
echo "" >> query_times.log

echo "condenser_api.get_discussions_by_comments" >> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":1, "method":"condenser_api.get_discussions_by_comments", "params":{"author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":1, "method":"condenser_api.get_discussions_by_comments", "params":{"author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":1, "method":"condenser_api.get_discussions_by_comments", "params":{"author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance"}}' $HOST ; } 2>> query_times.log
echo "" >> query_times.log

echo "condenser_api.get_post_discussions_by_payout" >> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"condenser_api.get_post_discussions_by_payout", "params":{}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"condenser_api.get_post_discussions_by_payout", "params":{}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"condenser_api.get_post_discussions_by_payout", "params":{}}' $HOST ; } 2>> query_times.log
echo "" >> query_times.log

echo "condenser_api.get_comment_discussions_by_payout" >> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"condenser_api.get_comment_discussions_by_payout", "params":{}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"condenser_api.get_comment_discussions_by_payout", "params":{}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"condenser_api.get_comment_discussions_by_payout", "params":{}}' $HOST ; } 2>> query_times.log
echo "" >> query_times.log

echo "bridge.get_profile" >> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_profile", "params":{"account":"blocktrades"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_profile", "params":{"account":"blocktrades"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_profile", "params":{"account":"blocktrades"}}' $HOST ; } 2>> query_times.log
echo "" >> query_times.log

echo "bridge.get_trending_topics" >> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_trending_topics", "params":{}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_trending_topics", "params":{}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_trending_topics", "params":{}}' $HOST ; } 2>> query_times.log
echo "" >> query_times.log

echo "bridge.get_post" >> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_post", "params":{"author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_post", "params":{"author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_post", "params":{"author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance"}}' $HOST ; } 2>> query_times.log
echo "" >> query_times.log

echo "bridge.get_ranked_posts (trending)" >> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_ranked_posts", "params":{"sort":"trending"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_ranked_posts", "params":{"sort":"trending"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_ranked_posts", "params":{"sort":"trending"}}' $HOST ; } 2>> query_times.log
echo "" >> query_times.log

echo "bridge.get_ranked_posts (hot)" >> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_ranked_posts", "params":{"sort":"hot"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_ranked_posts", "params":{"sort":"hot"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_ranked_posts", "params":{"sort":"hot"}}' $HOST ; } 2>> query_times.log
echo "" >> query_times.log

echo "bridge.get_ranked_posts (created)" >> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_ranked_posts", "params":{"sort":"created"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_ranked_posts", "params":{"sort":"created"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_ranked_posts", "params":{"sort":"created"}}' $HOST ; } 2>> query_times.log
echo "" >> query_times.log

echo "bridge.get_ranked_posts (promoted)"  >> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_ranked_posts", "params":{"sort":"promoted"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_ranked_posts", "params":{"sort":"promoted"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_ranked_posts", "params":{"sort":"promoted"}}' $HOST ; } 2>> query_times.log
echo "" >> query_times.log

echo "bridge.get_ranked_posts (payout)" >> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_ranked_posts", "params":{"sort":"payout"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_ranked_posts", "params":{"sort":"payout"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_ranked_posts", "params":{"sort":"payout"}}' $HOST ; } 2>> query_times.log
echo "" >> query_times.log

echo "bridge.get_ranked_posts (payout_comments)" >> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_ranked_posts", "params":{"sort":"payout_comments"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_ranked_posts", "params":{"sort":"payout_comments"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_ranked_posts", "params":{"sort":"payout_comments"}}' $HOST ; } 2>> query_times.log
echo "" >> query_times.log

echo "bridge.get_ranked_posts (muted)" >> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_ranked_posts", "params":{"sort":"muted"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_ranked_posts", "params":{"sort":"muted"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_ranked_posts", "params":{"sort":"muted"}}' $HOST ; } 2>> query_times.log
echo "" >> query_times.log

echo "bridge.get_account_posts (blog)" >> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_account_posts", "params":{"account":"blocktrades", "sort":"blog"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_account_posts", "params":{"account":"blocktrades", "sort":"blog"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_account_posts", "params":{"account":"blocktrades", "sort":"blog"}}' $HOST ; } 2>> query_times.log
echo "" >> query_times.log

echo "bridge.get_account_posts (feed)" >> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_account_posts", "params":{"account":"blocktrades", "sort":"feed"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_account_posts", "params":{"account":"blocktrades", "sort":"feed"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_account_posts", "params":{"account":"blocktrades", "sort":"feed"}}' $HOST ; } 2>> query_times.log
echo "" >> query_times.log

echo "bride.get_account_posts (posts)" >> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_account_posts", "params":{"account":"blocktrades", "sort":"posts"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_account_posts", "params":{"account":"blocktrades", "sort":"posts"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_account_posts", "params":{"account":"blocktrades", "sort":"posts"}}' $HOST ; } 2>> query_times.log
echo "" >> query_times.log

echo "bridge.get_account_posts (comments)" >> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_account_posts", "params":{"account":"blocktrades", "sort":"comments"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_account_posts", "params":{"account":"blocktrades", "sort":"comments"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_account_posts", "params":{"account":"blocktrades", "sort":"comments"}}' $HOST ; } 2>> query_times.log
echo "" >> query_times.log

echo "bridge.get_account_posts (replies)" >> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_account_posts", "params":{"account":"blocktrades", "sort":"replies"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_account_posts", "params":{"account":"blocktrades", "sort":"replies"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_account_posts", "params":{"account":"blocktrades", "sort":"replies"}}' $HOST ; } 2>> query_times.log
echo "" >> query_times.log

echo "bridge.get_account_posts (payout) " >> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_account_posts", "params":{"account":"blocktrades", "sort":"payout"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_account_posts", "params":{"account":"blocktrades", "sort":"payout"}}' $HOST ; } 2>> query_times.log
{ time curl -s -d '{"jsonrpc":"2.0", "id":7, "method":"bridge.get_account_posts", "params":{"account":"blocktrades", "sort":"payout"}}' $HOST ; } 2>> query_times.log
echo "" >> query_times.log

echo
echo
echo
echo "All done!"
