Lists comments from given discussion indicated by root post.

method: "database_api.list_comments"
params:
{
  "start": ["{root_author}","{root_permlink}","{start_author}","{start_permlink}"],

     root_author + root_permlink : mandatory; points to root post of discussion
     start_author + start_permlink : optional (can be left blank but not skipped), when given have to point to valid post; paging mechanism

  "limit": {number},

     optional 1..1000, default = 1000

  "order": "by_root"
}
