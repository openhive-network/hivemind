Lists not yet paid out replies ranked by pending payout, more paying first (order within the same payout is: newer first).
Slightly different post format but otherwise gives the same posts as bridge.get_ranked_posts with payout_comment sort.

method: "condenser_api.get_comment_discussion_by_payout"
params:
{
  "start_author":"{author}", "start_permlink":"{permlink}",

     start_author + start_permlink : optional, when given have to point to valid start post; paging mechanism (cuts out this and more paying replies)

  "limit":{number},

     optional, 1..100, default = 20

   "tag":"{tag}",

     optional, actually means category, when given have to point to valid category; narrows down results to posts with given category

   "truncate_body":{number},

     optional, default = 0 (meaning no truncation); reduces maximal size of post body, cutting out all excess

  "observer":"{account}"

     optional (can be skipped or passed empty), when passed has to point to valid account
     used to filter out posts authored by accounts ignored directly or indirectly by the observer
}