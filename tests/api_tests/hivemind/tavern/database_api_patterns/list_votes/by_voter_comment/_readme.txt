Lists posts voted on by given account.

method: "database_api.list_votes"
params:
{
  "start": ["{voter}","{start_author}","{start_permlink}"],

     voter : mandatory; points to valid account
     start_author + start_permlink : optional (can be left blank but not skipped), when given have to point to valid post; paging mechanism

  "limit": {number},

     optional 1..1000, default = 1000

  "order": "by_voter_comment"
}
