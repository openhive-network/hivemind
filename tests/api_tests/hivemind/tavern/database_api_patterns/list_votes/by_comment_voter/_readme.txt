Lists votes that were cast on given post.

method: "database_api.list_votes"
params:
{
  "start": ["{author}","{permlink}","{start_voter}"],

     author + permlink : mandatory, points to valid post
     start_voter : optional (can be left blank but not skipped), when given has to point to valid account; paging mechanism

  "limit": {number},

     optional 1..1000, default = 1000

  "order": "by_comment_voter"
}
