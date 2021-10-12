Lists posts created/reblogged by those followed by selected account.
Gives posts that were created/reblogged within last month.

method: "condenser_api.get_discussions_by_feed"
params:
{
  "tag":"{account}",

    mandatory, have to point on valid account whose feed we are looking at

  "start_author":"{author}" + "start_permlink":"{permlink}",

    optional, should point to valid post

  "limit":{number},

    optional, 1..100, default = 20

  "truncate_body":{number},

    optional, default = 0 (meaning no truncation); reduces maximal size of post body, cutting out all excess

  "filter_tags":[{list_of_tags}],

    has to be left empty, not supported

  "observer":"{account}"

     the following should be true, however just like in case of bridge.get_account_posts with feed sort, observer has no influence on the results:
     optional (can be skipped or passed empty), when passed has to point to valid account
     used to filter out posts authored by accounts ignored directly or indirectly by the observer
}

Notes for creating patterns:
It's possible to check original values on 0.23 hivemind. It has to be done manually, because in old version `last_month` was calculated from now() and not from head block timestamp making all results empty.

Example:
params: {"tag":"blocktrades","start_author":"michelle.gent","start_permlink":"dusty-the-demon-hunter-part-4","limit":10}
------------
a) Find id of account:
select * from hive_accounts where name = 'blocktrades'
found: `441`
------------
b) Find post's id for given author and permlink
SELECT id FROM hive_posts WHERE author = 'michelle.gent' AND permlink = 'dusty-the-demon-hunter-part-4'
found: `711172`
------------
Following query is taken from 0.23 version( for 5 million blocks ).
c) Put calculated values instead of _ID_ACCOUNT, _POST_ID, _LIMIT.
-----------
select hpc.post_id, hpc.author, hpc.permlink
FROM hive_posts_cache hpc
JOIN
(
SELECT post_id
FROM hive_feed_cache
JOIN hive_follows ON account_id = hive_follows.following AND state = 1
JOIN hive_accounts ON hive_follows.following = hive_accounts.id
WHERE hive_follows.follower = _ID_ACCOUNT(here 441)
 AND hive_feed_cache.created_at > ( '2016-09-15 19:47:15.0'::timestamp - interval '1 month' )
GROUP BY post_id 
          HAVING MIN(hive_feed_cache.created_at) <= ( 
                      SELECT MIN(created_at) FROM hive_feed_cache WHERE post_id = _POST_ID(here 711172)
               AND account_id IN (SELECT following FROM hive_follows
                                  WHERE follower = _ID_ACCOUNT(here 441) AND state = 1))
ORDER BY MIN(hive_feed_cache.created_at) DESC
) T ON hpc.post_id = T.post_id
ORDER BY post_id DESC
LIMIT _LIMIT(here 10)
