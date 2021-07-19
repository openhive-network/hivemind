Gives full information on given community. When observer is also given it adds context information for that account (see get_community_context)

method: "bridge.get_community"
params:
{
  "name": "{community}",
  
     mandatory, points to valid community (account in form of hive-number)

  "observer": "{account}"

     optional (can be skipped or passed empty); when passed points to valid account (not necessarily subscibed to that community)
}
