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
  
     optional (can be skipped or passed empty).
     If observer is specified, then in every sort case result will be supplemented with observer's blacklist.
     In case of sort by replies or feed, posts created by author muted by observer should not be visible,
     In case of sort by blog, posts, payout or comments, posts created by authors muted by observer should be marked as gray.     
}
