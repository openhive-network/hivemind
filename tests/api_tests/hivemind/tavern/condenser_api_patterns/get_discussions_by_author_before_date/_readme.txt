Lists posts with votes based on author from the most recent.
Similar to get_discussions_by_blog but does NOT serve reblogs.

method: "condenser_api.get_discussions_by_author_before_date"
params:
{
  "author":"{author}",

     mandatory, points to valid start account

  "start_permlink":"{permlink}"

     optional, with author when given have to point to valid start post; paging mechanism

  "limit":{number},

     optional, 1..100, default = 20

   "before_date":"{date}",

     optional, when given should point on start date; completely ignored

   "truncate_body":{number}

     optional, default = 0 (meaning no truncation); reduces maximal size of post body, cutting out all excess
}