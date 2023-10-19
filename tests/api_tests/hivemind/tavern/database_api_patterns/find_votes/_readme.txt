Lists votes that were cast on given post.
Pretty much the same as 'list_votes' with 'by_comment_voter' order, but without paging and with hardcoded 1000 limit.

method: "database_api.find_votes"
params:
{
  "author":"{author}", "permlink":"{permlink}"

     author + permlink : mandatory, points to valid post
}
