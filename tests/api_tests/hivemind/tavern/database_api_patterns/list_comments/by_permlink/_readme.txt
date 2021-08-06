Lists comments sorted by author and later with permlink, starting not earlier than given parameters.
Can be used also in situation when only part of author name or permlink is known.

method: "database_api.list_comments"
params:
{
  "start": ["{author}","{permlink}"],

     author : optional (can be left blank but not skipped), can be part of author name
     permlink : optional (can be left blank but not skipped), can be part of permlink; makes sense to pass it only with valid author, but it is not checked

  "limit": {number},

     optional 1..1000, default = 1000

  "order": "by_permlink"
}

