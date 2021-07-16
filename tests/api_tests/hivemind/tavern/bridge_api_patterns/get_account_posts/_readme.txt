Lists posts related to given account in selected way.

method: "bridge.get_account_posts"
params:
{
  "sort": "{order}",

     mandatory, determines order and filtering of returned posts
     values:
       "blog" - top posts authored by given account (excluding posts to communities - unless explicitely reblogged) plus reblogs ranked by creation/reblog time; paging cuts out given and newer posts
       "feed" - top posts from blogs of accounts that given account is following ranked by creation/reblog time, not older than last month; paging cuts out given and newer posts
       "posts" - top posts authored by given account, newer first; paging cuts out given and newer posts
       "comments" - replies authored by given account, newer first; paging cuts out given and newer posts
       "replies" - replies to posts of given account, newer first; paging cuts out given and newer posts
       "payout" - all posts authored by given account that were not yet cashed out, paying more first (then newer first); paging cuts out given and more paying posts

  "account": "{account}",

     mandatory, points to valid account
   
  "start_author":"{start_author}", "start_permlink":"{start_permlink}",

     start_author + start_permlink : optional (can be skipped or given empty), when given have to point to valid post; paging mechanism

  "limit": {number}

     optional, 1..100, default = 20

  "observer": "{account}"
  
     optional (can be skipped or passed empty), ignored for "blog", "feed" and "replies", otherwise when passed has to point to valid account
     used to fill blacklist stats and mark posts of authors blacklisted by observer
     (looks like it might be a bug since blacklist is applied to places where it makes no sense, while it is ignored where it would make sense to apply it)
     (update: still WIP, for the time being observer is basically ignored)
}
