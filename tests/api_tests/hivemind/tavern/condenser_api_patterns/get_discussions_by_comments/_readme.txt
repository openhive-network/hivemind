Lists replies to someone else's posts authored by given account, newer first.
Aside from different post format routine is pretty much the same as bridge.get_account_posts with comment sort.

method: "condenser_api.get_discussions_by_comments"
params:
{
  "start_author":"{author}",

    mandatory, points to valid account

  "start_permlink":"{permlink}",

    optional, when given along with start_author has to point to valid post, paging mechanism

  "limit":{number},

    optional, 1..100, default = 20

  "truncate_body":{number}

    optional, default = 0 (meaning no truncation); reduces maximal size of post body, cutting out all excess

  "filter_tags":[{list_of_tags}]

    has to be left empty, not supported
}