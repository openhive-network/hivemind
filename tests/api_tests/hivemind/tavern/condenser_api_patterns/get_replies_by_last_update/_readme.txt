Lists replies made to posts (both top posts and comments) of given blogger.
Contrary to name, time of last update is not considered - posts are ordered by creation time (newer first).

method: "condenser_api.get_replies_by_last_update"
params:
{
  "start_author":"{author}",

    mandatory, points to valid account; when start_permlink is omitted the account means blogger,
    when start_permlink is given it selects post from a result page and author of parent post is the blogger

  "start_permlink":"{permlink}",

    optional, when passed it has to point to valid post (paired with start_author)

  "limit":{number},

    optional, 1..100, default = 20

  "truncate_body":{number}

    optional, default = 0 (meaning no truncation); reduces maximal size of post body, cutting out all excess
}