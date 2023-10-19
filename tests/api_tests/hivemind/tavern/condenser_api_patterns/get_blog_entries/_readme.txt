Basically the same as get_blog, but with no post content, just author+permlink entries.
Lists posts from blog of given account newest first: top posts authored by given account and/or reblogged by it.
Does not filter for community posts (possibly a bug).

method: "condenser_api.get_blog_entries"
params:
{
  "account: "{account}",

     mandatory, points to valid account

  "start_entry_id": {number}

     optional, -1..any, default = 0, both -1 and 0 mean = {number of blog entries} - 1; part of paging mechanism (see below)

  "limit": {number}

     optional, 1..500 (0 functions as skipped), default = {start_entry_id} + 1; part of paging mechanism
     call selects up to limit blog posts starting at start_entry_id and going down by creation/reblog time
       ABW: as you can see it is not possible to select just the oldest post because adequate call of 0,1 produces
       newest post due to special meaning of 0 as start_entry_id (it is a bug IMHO)
}
