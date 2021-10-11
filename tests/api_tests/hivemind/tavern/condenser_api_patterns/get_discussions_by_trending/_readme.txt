Lists not yet paid out posts ranked by trending score (order within the same score is newer first).
Aside from different post format routine is very similar to bridge.get_ranked_posts with trending sort (does not handle community pinned posts in special way though).
Original differed from bridge version in that it considered all posts (unless community tag was passed) while bridge only uses top posts.
However there was a TODO comment in old version suggesting it should work like in bridge, so now it does.

method: "condenser_api.get_discussions_by_trending"
params:
{
  "start_author":"{author}", "start_permlink":"{permlink}",

    start_author + start_permlink : optional, when given have to point to valid start post; paging mechanism (cuts out this and more trending)

  "limit":{number},

    optional, 1..100, default = 20

  "tag":"{tag}",

    optional, turns on filtering for posts with given tag; when community tag is used it filters for community posts
    (compared to original version, posts that are only tagged with community tag, but don't belong to community, are no longer put in results)

  "truncate_body":{number},

    optional, default = 0 (meaning no truncation); reduces maximal size of post body, cutting out all excess

  "filter_tags":[{list_of_tags}],

    has to be left empty, not supported

  "observer":"{account}"

     optional (can be skipped or passed empty), when passed has to point to valid account
     used to filter out posts authored by accounts ignored directly or indirectly by the observer
}