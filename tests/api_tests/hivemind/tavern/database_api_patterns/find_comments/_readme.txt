Looks for given comments.

method: "database_api.find_comments"
params:
{
  "comments": [ ["{author}","{permlink}"],* ]

     author + permlink : optional (can be left blank or skipped), but only makes sense when it points to valid post
                         there can be up to 1000 such pairs in single call, duplicates are not squashed, invalid pairs are ignored
}

