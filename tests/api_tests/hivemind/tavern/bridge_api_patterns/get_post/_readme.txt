Gives single selected post.

method: "bridge.get_post"
params:
{
  "author":"{author}", "permlink":"{permlink}",

     author + permlink : mandatory, point to valid post

  "observer": "{account}"

     optional (can be skipped or given empty), used to add blacklist information to given post (currently ignored)
}
