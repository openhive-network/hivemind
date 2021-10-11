Lists replies to posts of given author that are not newer than given date.

method: "database_api.list_comments"
params:
{
  "start": ["{parent_author}","{update_date}","{start_author}","{start_permlink}"],

     parent_author : mandatory; points to valid account
     update_date : mandatory; update date in format "Y-m-d H:M:S" or "Y-m-dTH:M:S"
     start_author + start_permlink : optional (can be left blank but not skipped), when given have to point to valid post; paging mechanism

  "limit": {number},

     optional 1..1000, default = 1000

  "order": "by_last_update"
}
