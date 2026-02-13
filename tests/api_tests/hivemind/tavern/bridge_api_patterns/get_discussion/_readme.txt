Gives flattened discussion tree starting at given post.

method: "bridge.get_discussion"
params:
{
  "author":"{author}", "permlink":"permlink",

     author + permlink : mandatory, have to point to valid post; defines start of discussion tree

  "observer":"{account}"

     optional (can be skipped or passed empty), when passed has to point to valid account
     used to filter out discussion branches starting at posts authored by accounts ignored directly or indirectly by the observer

  "muted_reasons_filter": [0, 1, 2, 3, 4]

     optional array of integers (0-4), filters out posts that have any of the specified muted reasons:
       0 = MUTED_COMMUNITY_MODERATION (stored in hive_posts.muted_reasons)
       1 = MUTED_COMMUNITY_TYPE (stored in hive_posts.muted_reasons)
       2 = MUTED_PARENT (stored in hive_posts.muted_reasons)
       3 = MUTED_REPUTATION (dynamic: author has negative reputation / is_grayed)
       4 = MUTED_ROLE_COMMUNITY (dynamic: author has role_id = -2 in community)

}
