cmake_minimum_required(VERSION 3.10)

INCLUDE(tests_api/ApiTests.cmake)

ENABLE_TESTING()

ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind bridge account_notifications steemmeupscotty 1)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind bridge get_community hive-123456 alice)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind bridge get_ranked_posts trending hive alice)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind bridge list_all_subscriptions alice)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind bridge list_community_roles blocktrades)

ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind condenser_api get_account_reputations steemit 10)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind condenser_api get_account_votes alice)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind condenser_api get_active_votes drakos open-letter-to-justin-sun-and-the-steem-community)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind condenser_api get_blog drakos 0 1)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind condenser_api get_blog_authors drakos)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind condenser_api get_blog_entries tarazkp 0 10)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind condenser_api get_comment_discussions_by_payout [{"tag":"photography","limit":10,"truncate_body":0}])
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind condenser_api get_content tarazkp the-legacy-of-yolo)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind condenser_api get_content_replies tarazkp the-legacy-of-yolo)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind condenser_api get_discussions_by_active [{"tag":"photography","limit":10,"truncate_body":0}])
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind condenser_api get_discussions_by_author_before_date flaws my-first-experience-integrating-steem-into-chess-in-my-state-or-a-lot-of-photos-3 2020-03-01T00:00:00 1)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind condenser_api get_discussions_by_blog [{"tag":"tarazkp","limit":2,"truncate_body":0}])
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind condenser_api get_discussions_by_cashout [{"tag":"tarazkp","limit":2,"truncate_body":0}])
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind condenser_api get_discussions_by_children [{"tag":"tarazkp","limit":2,"truncate_body":0}])
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind condenser_api get_discussions_by_comments tarazkp the-legacy-of-yolo 5)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind condenser_api get_discussions_by_created [{"tag":"blocktrades","limit":1}])
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind condenser_api get_discussions_by_feed steemtools steempeak introducing-peaklock-and-keys-management 3)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind condenser_api get_discussions_by_hot [{"tag":"tarazkp","limit":2,"truncate_body":0}])
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind condenser_api get_discussions_by_promoted [{"tag":"tarazkp","limit":2,"truncate_body":0}])
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind condenser_api get_discussions_by_trending [{"tag":"tarazkp","limit":2,"truncate_body":0}])
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind condenser_api get_discussions_by_votes [{"tag":"tarazkp","limit":2,"truncate_body":0}])
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind condenser_api get_feed steemit 0 1)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind condenser_api get_feed_entries steemit 0 1)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind condenser_api get_follow_count steemmeupscotty)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind condenser_api get_followers steemit null blog 10)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind condenser_api get_following steemit null blog 10)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind condenser_api get_post_discussions_by_payout [{"tag":"tarazkp","limit":2,"truncate_body":0}])
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind condenser_api get_reblogged_by tarazkp the-legacy-of-yolo)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind condenser_api get_replies_by_last_update tarazkp the-legacy-of-yolo 10)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind condenser_api get_tags_used_by_author steemit)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind condenser_api get_trending_tags blocktrades 1)

ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind follow_api get_account_reputations 1 blocktrades 1)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind follow_api get_blog 1 blocktardes 0 1)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind follow_api get_blog_entries 1 blocktrades 0 1)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind follow_api get_follow_count 1 blocktrades)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind follow_api get_followers 1 steemit \"\" blog 10)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind follow_api get_following 1 blocktrades \"\" blog 10)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind follow_api get_reblogged_by 1 steemit firstpost)

ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind tags_api get_active_votes flaws my-first-experience-integrating-steem-into-chess-in-my-state-or-a-lot-of-photos-3) 
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind tags_api get_comment_discussions_by_payout blocktrades 1)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind tags_api get_content_replies flaws my-first-experience-integrating-steem-into-chess-in-my-state-or-a-lot-of-photos-3)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind tags_api get_discussion steemmeupscotty black-dog-on-a-hong-kong-sunrise-animal-landscape-photography)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind tags_api get_discussions_by_active blocktrades 1)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind tags_api get_discussions_by_author_before_date flaws my-first-experience-integrating-steem-into-chess-in-my-state-or-a-lot-of-photos-3 2020-03-01T00:00:00 1)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind tags_api get_discussions_by_blog blocktrades 1)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind tags_api get_discussions_by_cashout blocktrades 1)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind tags_api get_discussions_by_children blocktrades 1)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind tags_api get_discussions_by_comments tarazkp the-legacy-of-yolo 1)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind tags_api get_discussions_by_created blocktrades 1)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind tags_api get_discussions_by_feed blocktrades 1)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind tags_api get_discussions_by_hot blocktrades 1)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind tags_api get_discussions_by_promoted blocktrades 1)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind tags_api get_discussions_by_trending blocktrades 1)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind tags_api get_discussions_by_votes blocktrades 1)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind tags_api get_post_discussions_by_payout blocktrades 1)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind tags_api get_replies_by_last_update flaws my-first-experience-integrating-steem-into-chess-in-my-state-or-a-lot-of-photos-3 1)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind tags_api get_tags_used_by_author flaws)
ADD_API_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind tags_api get_trending_tags blocktrades 1)

ADD_API_PYREST_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind 5000000 bridge_api )
ADD_API_PYREST_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind 5000000 condenser_api )
ADD_API_PYREST_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind 5000000 database_api )
ADD_API_PYREST_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind 5000000 follow_api )
ADD_API_PYREST_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind 5000000 hive_api )
ADD_API_PYREST_TEST(${CMAKE_BINARY_DIR}/tests/tests_api ${CMAKE_CURRENT_SOURCE_DIR}/tests_api hivemind 5000000 tags_api )











