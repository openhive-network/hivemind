Lists notifications related to given post. Currently limited to not older than (arbitrary number) 90 days since head block.

method: "bridge.post_notifications"
params:
{
  "author":"{author}", "permlink":"{permlink}",
  
     author + permlink : mandatory, points to valid post

  "min_score": {number}

     optional, 0..100, default = 25, minimal score of notifications to show

  "last_id": {number},

     optional, indicates newest notification to show; paging mechanism

  "limit": {number}

     optional, 1..100, default = 100
}
