Lists posts depending on given ranking criteria and filters.

method: "bridge.get_ranked_posts"
params:
{
  "sort": "{order}",

     mandatory, determines order and filtering of returned posts
     values:
       "trending" - [if tag is community pinned posts first], top posts with highest trending score first; paging cuts out given and more trending posts
       "hot" - top posts with highest hot score first; paging cuts out given and hotter posts
       "created" - [if tag is community pinned posts first], newest top posts first (grayed out not considered); paging cuts out given and newer posts
       "payout" - only posts that will cashout between 12 and 36 hours from head block are considered, posts with higher pending payout first; paging cuts out given and higher payout posts
       "payout_comments" - only replies are considered, posts with higher pending payout first; paging cuts out given and higher payout posts
       "muted" - grayed out posts that are to receive nonzero payout are considered, posts with higher pending payout first; paging cuts out given and higher payout posts
     with the exception of "created" only not yet cashed out posts are considered

  "start_author":"{start_author}", "start_permlink":"{start_permlink}",

     start_author + start_permlink : optional (can be skipped or given empty), when given have to point to valid post; paging mechanism

  "limit": {number}

     optional, 1..100, default = 20

  "tag": "{tag_or_special_or_community}",
  
     optional (can be skipped or passed empty)
     values:
       "my" (with observer) - turns on filtering for posts within communities subscribed to by observer
       "all" - same as default none/blank
       "hive-{number}" - has to point to valid community; turns on filtering for posts within given community
       "{tag}" - has to point to valid tag; turns on filtering for posts with given tag (given category in case of 'payout' and 'payout_comments')

  "observer": "{account}"

     mandatory for "my" tag, points to valid account; when given supplements blacklists stats in posts and
     filters out posts of muted authors (with exception of "muted" sort)
}
