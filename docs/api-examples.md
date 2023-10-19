# hive.condenser_api

```
http -j post http://localhost:8080 jsonrpc=2.0 id=1 method=condenser_api.get_follow_count params:='{"account":"test-safari"}'
http -j post http://localhost:8080 jsonrpc=2.0 id=1 method=condenser_api.get_followers params:='{"account":"test-safari","start":"","follow_type":"blog","limit":10}'
http -j post http://localhost:8080 jsonrpc=2.0 id=1 method=condenser_api.get_followers params:='{"account":"test-safari","start":"money-dreamer","follow_type":"blog","limit":3}'
http -j post http://localhost:8080 jsonrpc=2.0 id=1 method=condenser_api.get_following params:='{"account":"test-safari","start":"","follow_type":"blog","limit":10}'

http -j post http://localhost:8080 jsonrpc=2.0 id=1 method=condenser_api.get_discussions_by_trending params:='{"start_author":"","start_permlink":"","tag":"","limit":10}'
http -j post http://localhost:8080 jsonrpc=2.0 id=1 method=condenser_api.get_discussions_by_trending params:='{"start_author":"fredrikaa","start_permlink":"why-i-bought-my-brother-steem-for-christmas-and-how-you-can-do-the-same","tag":"","limit":2}'

http -j post http://localhost:8080 jsonrpc=2.0 id=1 method=condenser_api.get_discussions_by_blog params:='{"tag":"test-safari"}'
http -j post http://localhost:8080 jsonrpc=2.0 id=1 method=condenser_api.get_discussions_by_blog params:='{"start_author":"test-safari","start_permlink":"3umrbh-november-spam","tag":"test-safari","limit":3}'

http -j post http://localhost:8080 jsonrpc=2.0 id=1 method=condenser_api.get_discussions_by_feed params:='{"tag":"test-safari"}'
http -j post http://localhost:8080 jsonrpc=2.0 id=1 method=condenser_api.get_discussions_by_feed params:='{"tag":"test-safari","limit":3,"start_author":"steemitblog","start_permlink":"steemit-winter-update-2017-reflection-our-vision-statement-and-mission-and-a-look-forward"}'

http -j post http://localhost:8080 jsonrpc=2.0 id=1 method=condenser_api.get_discussions_by_comments params:='{"start_author":"test-safari","start_permlink":""}'
http -j post http://localhost:8080 jsonrpc=2.0 id=1 method=condenser_api.get_discussions_by_comments params:='{"start_author":"test-safari","start_permlink":"re-test-safari-re-test-safari-i-m-hodling-20180122t213927522z","limit":3}'

http -j post http://localhost:8080 jsonrpc=2.0 id=1 method=condenser_api.get_replies_by_last_update params:='{"start_author":"test-safari","start_permlink":""}'
http -j post http://localhost:8080 jsonrpc=2.0 id=1 method=condenser_api.get_replies_by_last_update params:='{"start_author":"test-safari","start_permlink":"re-test-safari-re-test-safari-i-m-hodling-20180122t213927522z","limit":3}'
http -j post http://localhost:8080 jsonrpc=2.0 id=1 method=condenser_api.get_replies_by_last_update params:='["test-safari","re-test-safari-re-test-safari-i-m-hodling-20180122t213927522z",3]'

http -j post http://localhost:8080 jsonrpc=2.0 id=1 method=condenser_api.get_content params:='{"author":"test-safari","permlink":"34gfex-december-spam"}'
http -j post http://localhost:8080 jsonrpc=2.0 id=1 method=condenser_api.get_content_replies params:='{"parent":"test-safari","parent_permlink":"34gfex-december-spam"}'

http -j post http://localhost:8080 jsonrpc=2.0 id=1 method=condenser_api.get_state params:='{"path":"spam/@test-safari/34gfex-december-spam"}'
http -j post http://localhost:8080 jsonrpc=2.0 id=1 method=condenser_api.get_state params:='{"path":"trending"}'

http -j post http://localhost:8080 jsonrpc=2.0 id=1 method=condenser_api.get_discussions_by_author_before_date params:='["test-safari","","2128-03-20T20:27:30",10]'
http -j post http://localhost:8080 jsonrpc=2.0 id=1 method=condenser_api.get_blog params:='["test-safari", 5, 3]'
http -j post http://localhost:8080 jsonrpc=2.0 id=1 method=condenser_api.get_blog_entries params:='["test-safari", 5, 3]'

```


# hive

```
http -j post http://localhost:8080 jsonrpc=2.0 id=1 method=hive.db_head_state params:='{}'

http -j post http://localhost:8080 jsonrpc=2.0 id=1 method=hive.get_followers params:='{"account":"test-safari","skip":0,"limit":10}'
http -j post http://localhost:8080 jsonrpc=2.0 id=1 method=hive.get_following params:='{"account":"test-safari","skip":0,"limit":10}'

http -j post http://localhost:8080 jsonrpc=2.0 id=1 method=hive.get_follow_count params:='{"account":"test-safari"}'

http -j post http://localhost:8080 jsonrpc=2.0 id=1 method=hive.get_user_feed params:='{"account":"test-safari","skip":0,"limit":20,"ctx":"test-safari"}'
http -j post http://localhost:8080 jsonrpc=2.0 id=1 method=hive.get_blog_feed params:='{"account":"test-safari","skip":0,"limit":20,"ctx":"test-safari"}'

http -j post http://localhost:8080 jsonrpc=2.0 id=1 method=hive.get_related_posts params:='{"account":"test-safari","permlink":"tps-report-4-calm-before-the-storm"}'

http -j post http://localhost:8080 jsonrpc=2.0 id=1 method=hive.payouts_total
http -j post http://localhost:8080 jsonrpc=2.0 id=1 method=hive.payouts_last_24h

http -j post http://localhost:8080 jsonrpc=2.0 id=1 method=hive.search params:='{"query":"test-"}'
```


# steemd.legacy (deprecated)

```
http -j post https://api.hive.blog jsonrpc=2.0 id=1 method=call params:='["follow_api","get_follow_count",["test-safari"]]'
http -j post https://api.hive.blog jsonrpc=2.0 id=1 method=call params:='["follow_api","get_followers",["test-safari","", "blog", 5]]'
http -j post https://api.hive.blog jsonrpc=2.0 id=1 method=call params:='["follow_api","get_following",["test-safari","", "ignore", 2]]'

http -j post https://api.hive.blog jsonrpc=2.0 id=1 method=call params:='["database_api","get_content",["test-safari", "34gfex-december-spam"]]'
```
