Gives list of notifications for given account that are newer than last read timestamp of that account.

method: "bridge.unread_notifications"
params:
{
  "account": "{account}",
  
     mandatory, points to valid account

  "min_score": {number}

     optional, 0..100, default = 25, minimal score of notifications to show
}
