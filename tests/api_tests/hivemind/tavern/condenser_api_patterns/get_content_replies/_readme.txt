Lists replies for given post.
Current version gives output matching that of old Fat Node (database_api style posts). Original get_content_replies output
is still available through tags_api.get_content_replies

method: "condenser_api.get_content_replies"
params:
{
  "author": "{author}", "permlink": {permlink}
  
    author + permlink : mandatory, points to valid post
}
