Gives flattened discussion tree starting at given post.

method: "bridge.get_discussion"
params:
{
  "author":"{author}", "permlink":"permlink",
  
     author + permlink : mandatory, have to point to valid post; defines start of discussion tree

  "observer":"{account}"

     optional (can be skipped or passed empty), when passed has to point to valid account
     used to filter out discussion branches starting at posts authored by accounts ignored directly or indirectly by the observer

}
