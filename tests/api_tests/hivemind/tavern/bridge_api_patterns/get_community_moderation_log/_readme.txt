Returns the moderation log for a given community with optional filtering by action type.

method: "bridge.get_community_moderation_log"
params:
{
  "community":"{name}",

    mandatory, points to community

  "action_type":"{string}",

    optional, filter by action: "set_role", "set_title", "mute_post",
    "unmute_post", "pin_post", "unpin_post", "flag_post"

  "last_date":"{datetime}",

    optional, cursor for keyset pagination (entries with date < last_date)

  "limit":{number}

    optional, 1..1000; default = 100
}

NOTE: Pattern files contain placeholder data. After the first sync with mock data,
run tests with TAVERN_DISABLE_COMPARATOR=true, then copy the .out.json files to
.pat.json to populate the actual expected patterns.
