Gives basic information about given account.

method: "bridge.get_profile"
params:
{
  "account": "{account}",

     mandatory, points to valid account

  "observer": "{account}"

     optional (can be skipped or given empty), when given points to valid account; used to add information about relationship of observer with given profile account
}
