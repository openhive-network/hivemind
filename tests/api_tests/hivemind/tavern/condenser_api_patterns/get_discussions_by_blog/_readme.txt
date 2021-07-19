Lists posts from blog of given account newest first: top posts authored by given account and/or reblogged by it.
Aside from different post format routine is similar to bridge.get_account_posts with "blog" sort. The main difference is that bridge version filters out
community posts, while this one does not.

method: "condenser_api.get_discussions_by_blog"
params:
{
  "tag":"{account}",

    mandatory, points to valid account; author of blog

  "start_author":"{author}", "start_permlink":"{permlink}",

    start_author + start_permlink : optional, when given have to point to valid start post; paging mechanism (cuts out this and newer posts/reblogs)

  "limit":{number},

    optional, 1..100, default = 20

  "truncate_body":{number}

    optional, default = 0 (meaning no truncation); reduces maximal size of post body, cutting out all excess

  "filter_tags":[{list_of_tags}]

    has to be left empty, not supported
}