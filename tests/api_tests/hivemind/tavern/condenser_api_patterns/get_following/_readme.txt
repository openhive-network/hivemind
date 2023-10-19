Gives accounts which given account follows/ignores.

method: "condenser_api.get_following"
params:
{
  "account":"{account}",

    mandatory, points to valid account

  "start":"{account}"

    optional, when provided has to point to valid account, paging mechanism (cuts out this and newer follows)

  "limit:{number}

    optional, 1..1000, default = 1000

  "follow_type":"{follow_type}"

    optional, 'blog'/'ignore' (should be extended with 'blacklists' etc.), default = 'blog'
}