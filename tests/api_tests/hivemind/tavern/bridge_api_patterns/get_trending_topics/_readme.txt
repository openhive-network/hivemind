Lists top communities ranked by sum of pending payouts, number of distinct authors, posts and subscribers.
When there is not enough ranked communities (not possible on fully synced but happens in tests) some hardcoded topics are added.

method: "bridge.get_trending_topics"
params:
{
  "limit": {number},

     mandatory 1..25, default = 10

  "observer": "{account}"

     optional, ignored (probably not yet implemented functionality)
}
