Gives a list of root posts similar in wording to the given post (BM25 more-like-this over title and body)

method: "search-api.find_similar"
params:
{
  "author":"{author}", "permlink":"{permlink}"

     mandatory, points to a valid post; the post itself is never in the result; a comment, or a post
     with no distinctive terms, gives an empty list

  "limit": {number}

     optional, 1..100, default = 20

  "observer": "{account}"

     points to valid account; when given supplements blacklists stats in posts and
     filters out posts of muted authors

  "truncate_body": {number},

      optional, default = 0 (meaning no truncation); reduces maximal size of post body, cutting out all excess
}

Useful tip for testing: "ignoreall" (mock data) mutes gtg, alice, gavvet and others.
