#!/bin/bash

echo "test get_content (REQUIRED params: author, permlink;   OPTIONAL params: none)"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"condenser_api.get_content","params":{"author":"jes2850", "permlink":"happy-kitty-sleepy-kitty-purr-purr-purr"} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"condenser_api.get_content","params":{"author":"jes2850", "permlink":"happy-kitty-sleepy-kitty-purr-purr-purr"} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test get_content_replies (REQUIRED params: author, permlink;   OPTIONAL params: none)"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"condenser_api.get_content_replies","params":{"author":"blocktrades", "permlink":"should-long-term-hive-proposals-cost-more-to-create"} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"condenser_api.get_content_replies","params":{"author":"blocktrades", "permlink":"should-long-term-hive-proposals-cost-more-to-create"} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test get_discussions_by_trending no params (REQUIRED params: none;    OPTIONAL params: start_author, start_permlink, limit, tag, truncate_body, filter_tags)"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"condenser_api.get_discussions_by_trending","params":{} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"condenser_api.get_discussions_by_trending","params":{} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test get_discussions_by_trending author and permlink (REQUIRED params: none;    OPTIONAL params: start_author, start_permlink, limit, tag, truncate_body, filter_tags)"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"condenser_api.get_discussions_by_trending","params":{"start_author":"blocktrades", "start_permlink":"should-long-term-hive-proposals-cost-more-to-create"} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"condenser_api.get_discussions_by_trending","params":{"start_author":"blocktrades", "start_permlink":"should-long-term-hive-proposals-cost-more-to-create"} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test get_discussions_by_trending with tag(REQUIRED params: none;    OPTIONAL params: start_author, start_permlink, limit, tag, truncate_body, filter_tags)"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"condenser_api.get_discussions_by_trending","params":{"tag":"gaming"} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"condenser_api.get_discussions_by_trending","params":{"tag":"gaming"} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test get_discussions_by_hot"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"condenser_api.get_discussions_by_hot","params":{} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"condenser_api.get_discussions_by_hot","params":{} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test get_discussions_by_promoted"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"condenser_api.get_discussions_by_promoted","params":{} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"condenser_api.get_discussions_by_promoted","params":{} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test get_discussions_by_created"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"condenser_api.get_discussions_by_created","params":{} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"condenser_api.get_discussions_by_created","params":{} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test get_discussions_by_blog"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"condenser_api.get_discussions_by_blog","params":{"tag":"blocktrades"} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"condenser_api.get_discussions_by_blog","params":{"tag":"blocktrades"} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test get_discussions_by_feed"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"condenser_api.get_discussions_by_feed","params":{"tag":"blocktrades"} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"condenser_api.get_discussions_by_feed","params":{"tag":"blocktrades"} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test get_discussions_by_comments"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"condenser_api.get_discussions_by_comments","params":{"start_author":"blocktrades"} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"condenser_api.get_discussions_by_comments","params":{"start_author":"blocktrades"} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test trending"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"trending", "limit":5} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"trending", "limit":5} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test hot"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"hot", "limit":5} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"hot", "limit":5} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test created"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"created", "limit":5} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"created", "limit":5} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test promoted"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"promoted", "limit":5} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"promoted", "limit":5} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test payout"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"payout", "limit":5} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"payout", "limit":5} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test payout_comments"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"payout_comments", "limit":5} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"payout_comments", "limit":5} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test muted"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"muted", "limit":5} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"muted", "limit":5} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test trending with author and permlink"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"trending", "limit":5, "start_author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance"} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"trending", "limit":5, "start_author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance"} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test hot with author and permlink"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"hot", "limit":5, "author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance"} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"hot", "limit":5, "author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance"} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test created with author and permlink"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"created", "limit":5, "author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance"} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"created", "limit":5, "author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance"} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test promoted with author and permlink"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"promoted", "limit":5, "author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance"} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"promoted", "limit":5, "author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance"} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test payout with author and permlink"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"payout", "limit":5, "author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance"} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"payout", "limit":5, "author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance"} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test payout comments with author and permlink"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"payout_comments", "limit":5, "author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance"} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"payout_comments", "limit":5, "author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance"} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test muted with author and permlink"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"muted", "limit":5, "author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance"} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"muted", "limit":5, "author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance"} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test trending with author and permlink and tag of all"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"trending", "limit":5, "author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance", "tag":"all"} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"trending", "limit":5, "author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance", "tag":"all"} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test hot with author and permlink and tag of all"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"hot", "limit":5, "author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance", "tag":"all"} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"hot", "limit":5, "author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance", "tag":"all"} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test created with author and permlink and tag of all"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"created", "limit":5, "author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance", "tag":"all"} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"created", "limit":5, "author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance", "tag":"all"} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test promoted with author and permlink and tag of all"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"promoted", "limit":5, "author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance", "tag":"all"} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"promoted", "limit":5, "author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance", "tag":"all"} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test payout with author and permlink and tag of all"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"payout", "limit":5, "author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance", "tag":"all"} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"payout", "limit":5, "author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance", "tag":"all"} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test payout comments with author and permlink and tag of all"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"payout_comments", "limit":5, "author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance", "tag":"all"} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"payout_comments", "limit":5, "author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance", "tag":"all"} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test muted with author and permlink and tag of all"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"muted", "limit":5, "author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance", "tag":""} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"muted", "limit":5, "author":"blocktrades", "permlink":"image-server-cluster-development-and-maintenance", "tag":""} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

#--------------------------------------------------------------------------------------------------------
echo "RANKED POSTS"
echo ""

echo "test trending with no author/permlink but with tag"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"trending", "limit":5, "tag":"games"} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"trending", "limit":5, "tag":"games"} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test hot with no author/permlink but with tag"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"hot", "limit":5, "tag":"games"} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"hot", "limit":5, "tag":"games"} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test created with no author/permlink but with tag"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"created", "limit":5, "tag":"games"} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"created", "limit":5, "tag":"games"} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test promoted with  no author/permlink but with tag"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"promoted", "limit":5, "tag":"games"} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"promoted", "limit":5, "tag":"games"} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test payout with no author/permlink but with tag"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"payout", "limit":5, "tag":"games"} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"payout", "limit":5, "tag":"games"} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test payout comments with no author/permlink but with tag"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"payout_comments", "limit":5, "tag":"games"} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"payout_comments", "limit":5, "tag":"games"} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test muted with no author/permlink but with tag"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"muted", "limit":5, "tag":"games"} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"muted", "limit":5, "tag":"games"} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test with garbage params, should fail but not crash out"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"mutead", "limit":5, "tag":"games"} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_ranked_posts","params":{"sort":"mutead", "limit":5, "tag":"games"} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test get_post"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_post","params":{"author":"jes2850", "permlink":"happy-kitty-sleepy-kitty-purr-purr-purr"} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_post","params":{"author":"jes2850", "permlink":"happy-kitty-sleepy-kitty-purr-purr-purr"} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json

echo "test get_post with garbage. should fail but not crash out"
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_post","params":{"author":"jes2850", "permlink":"happy-kitty-sleepy-kitty-purr-purr"} }' http://steem-3:8085 > old_result
curl -s -d '{"jsonrpc":"2.0","id":1,"method":"bridge.get_post","params":{"author":"jes2850", "permlink":"happy-kitty-sleepy-kitty-purr-purr"} }' http://127.0.0.1:8085 > new_result
cat old_result | jq . > old_pretty.json
cat new_result | jq . > new_pretty.json
diff old_pretty.json new_pretty.json
