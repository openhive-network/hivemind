Lists notifications for given account. Currently limited to not older than (arbitrary number) 90 days since head block.

method: "bridge.account_notifications"
params:
{
  "account": "{account}",
  
     mandatory, points to valid account

  "min_score": {number}

     optional, 0..100, default = 25, minimal score of notifications to show

  "last_id": {number},

     optional, indicates newest notification to show; paging mechanism

  "limit": {number}

     optional, 1..100, default = 100

  "type": [{string}, ...]

     optional, names of notification types to return (e.g. ["vote", "reply", "follow"]);
     omitted, null or empty returns all types; unknown names are rejected

  "community": "{community}"

     optional, existing community name (e.g. "hive-123456"); returns only notifications
     concerning that community (community operations and activity on posts in it) plus
     notifications tied to no post or community at all (e.g. follow)
}

Notifications concerning a community carry an additional "community" field with its name.
