Lists categories ordered by sum of pending payouts, with stats summary about comments and top posts.

method: "condenser_api.get_trending_tags"
params:
{
  "start_tag":"{tag}",

    optional, when given has to point to valid tag; paging mechanism (cuts out this and more paying categories)

  "limit":{number}

    optional, 1..250, default = 250
}