Lists communities depending on chosen ranking.

method: "bridge.list_communities"
params:
{
  "last":"{name}",

    optional, name of community; paging mechanism (cuts out this and "higher" communities, depends on chosen ranking)

  "limit":{number},

    optional, range 1..100; default = 100

  "query":"{title}",

    optional, when given turns on filtering for given set of words - words are looked for in 'title' and 'about' fields

  "sort": "{order}",

    optional, determines order of returned communities, default = "rank"
    values:
      "rank" - communities with highest rank (trending) score first
      "new" - newest communities first
      "subs" - communities with largest number of subscribers first

  "observer":"{account}"

    optional (can be skipped or passed empty), when passed has to point to valid account
    used to show relation between account and community (subscribed, role and title)

}
