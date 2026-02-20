# Error Notification Behavior: SQL vs Python Community Op Processing

## Summary

The SQL massive sync path (`process_community_op` in `massive_sync.sql`) handles community operation validation failures differently than the Python path (`Community` class in `hive/indexer/community.py`). Neither path is more or less strict in what it accepts, but they differ in whether users/admins are notified about rejected operations.

## Behavior Difference

### Python Path (current `develop` behavior)

When a community operation fails validation (e.g., title exceeds max length, invalid URL, missing required field):

1. The validation `assert` raises `AssertionError`
2. The exception is caught in `Community.validate()` (community.py:330)
3. An **error notification** (type `error`) is generated and stored in `hive_notification_cache`
4. The notification is visible to the community admin in their notification feed

Example notification:
```json
{
  "type": "error",
  "msg": "error: exceeds max len: title",
  "score": 35,
  "url": "c/hive-171744"
}
```

### SQL Path (new behavior)

When a community operation fails validation:

1. The validation function returns `false`
2. The handler exits early with `RETURN _counter_in`
3. **No notification is generated** — the invalid operation is silently ignored
4. The user/admin has no visibility into why their operation was rejected

## What This Affects

Both paths validate the same rules:
- `updateProps`: title maxlen=20, title minlen=3, about maxlen=120, lang=2 chars, description maxlen=1000, flag_text maxlen=1000, avatar_url/cover_url must start with http(s)://, type_id must be 1-3
- `setRole`: role maxlen=16, must be valid role name
- `setUserTitle`: title maxlen=32
- `mutePost`/`unmutePost`/`pinPost`/`unpinPost`: notes maxlen=120

## Impact on Tests

12 notification test patterns changed because:
1. `error`-type notifications no longer appear in results (they were never generated)
2. The notification list shifts, exposing different notifications at page boundaries
3. Notification IDs change slightly due to different processing order in the SQL path

Affected tests: `account_notifications/{gtg,dantheman,gtg_2,hive-171744,ismember}`, `post_notifications/{max_limit,paginated,steve-walschot}`, `unread_notifications/{abit,elyaque,min_score,steemit}`

## Decision Needed

Should the SQL path generate error notifications for invalid community operations?

**Arguments for generating them (match Python):**
- Community admins can see when invalid operations are submitted
- Useful for debugging community configuration issues
- Users know their operation was received but rejected (vs wondering if it was lost)

**Arguments against (keep current SQL behavior):**
- Error notifications are noise — users can't act on them from the notification feed
- Invalid operations on-chain are permanent; notifying about them doesn't help
- Simpler code path, fewer writes to notification table
- The blockchain itself doesn't enforce these limits — hivemind is imposing them as soft rules

**If we decide to add error notifications to SQL**, the implementation would be:
- Add an `_error_notify` helper in `process_community_op` that inserts into `hive_notification_cache` with `type_id = 10` (error)
- Call it at each early-return validation point, passing the error message
- This would be similar to the existing error notification at line 1668 (community-not-found)
