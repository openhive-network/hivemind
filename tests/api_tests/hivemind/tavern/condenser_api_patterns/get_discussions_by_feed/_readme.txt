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
