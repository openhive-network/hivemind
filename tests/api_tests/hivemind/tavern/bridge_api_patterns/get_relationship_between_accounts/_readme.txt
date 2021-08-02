Tells what relations connect given accounts from the perspective of first account.

method: "bridge.get_relationship_between_accounts"
params:
{
  "account1": "{account}",

     mandatory, points to valid account

  "account2": "{account}",

     mandatory, points to valid account
   
  "observer": "{account}"

     optional, ignored (most likely not yet implemented extra for supplementing blacklist information)
}
