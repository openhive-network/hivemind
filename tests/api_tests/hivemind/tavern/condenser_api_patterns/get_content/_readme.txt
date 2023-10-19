Gives content for given post.
Current version gives output matching that of old Fat Node (database_api style posts). Original get_content output
is still available through tags_api.get_discussion

method: "condenser_api.get_content"
params:
{
  "author": "{author}", "permlink": {permlink},
  
    author + permlink : mandatory, points to valid post

  "observer": "{account}"

    optional, used for muted votes and blacklists (that functionality was removed and now observer is completely ignored - it will most likely stay that way)
}
