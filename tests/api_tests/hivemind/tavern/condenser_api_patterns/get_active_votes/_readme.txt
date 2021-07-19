Lists votes for given post (slightly less detailed than database_api.find_votes, also with hardcoded limit of 1000 votes).
Original patterns from fat node.

method: "condenser_api.get_active_votes"
params:
{
  "author":"{author}", "permlink":"{permlink}"

     author + permlink : mandatory, points to valid post
}
