Gives basic information about given account list.

method: "bridge.get_profiles"
params:
{
  "accounts": "[{account}]",

     mandatory, points to valid account list, all must be valid

  "observer": "{account}"

     optional (can be skipped or given empty), when given points to valid account; used to add information about relationship of observer with given profile account
}
