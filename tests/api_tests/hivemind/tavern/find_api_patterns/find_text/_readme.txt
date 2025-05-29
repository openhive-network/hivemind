Gives a list of root posts which contains words

method: "find_api.find_text"
params:
{
  "pattern" : words to find
  "sort": "{order}",

     mandatory, determines order and filtering of returned posts
     values:
       "relevant" - gives posts n order defined by postgres ts_rank algorithm https://www.postgresql.org/docs/current/textsearch-controls.html#TEXTSEARCH-RANKING
       "created" - newest top posts first (grayed out not considered); paging cuts out given and newer posts

  "start_author":"{start_author}", "start_permlink":"{start_permlink}",

     start_author + start_permlink : optional (can be skipped or given empty), when given have to point to valid post; paging mechanism

  "limit": {number}

     optional, 1..100, default = 20


  "observer": "{account}"

     points to valid account; when given supplements blacklists stats in posts and
     filters out posts of muted authors (with exception of "muted" sort)

  "truncate_body": {number},

      optional, default = 0 (meaning no truncation); reduces maximal size of post body, cutting out all excess
}

Useful tip for testing: gtg named his cat "Nyunya", and this word occurs only once in all posts to 5M (look at @gtg/hello-world)