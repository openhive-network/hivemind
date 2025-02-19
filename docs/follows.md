# Hive Follows Design

## Overview

All accounts are able to perform follow action on another account in order to:
- stay up to date with posts by the author you are interested in
- isolate posts by authors that the user is not interested in
- put user on blacklist and mark posts created by him

It is also possible to follow other account blacklists and mutes. So if user want to have the same mutes or/and blacklists as another user, there is such possibility.

#### Follow Actions

There are 16 follow actions:
1. **blog** - user follows another user
2. **follow** - the same as **blog**
3. **ignore** - user mutes another user, what results with hiding posts created by muted user, in some cases these posts can be grayed.
4. **blacklist** - marks user as blacklisted and his posts will be marked with 'my blacklist'
5. **follow_blacklist** - user follows another user's list of blacklisted users and will see 'blacklisted by <user>' if someone post is blacklisted by one of user who's blacklist is followed
6. **unblacklist** - removes user from own blacklist
7. **unfollow_blacklist** - stop following another user's list of blacklisted users.
8. **follow_muted** - user follows another user's list of muted users and posts created by these users will be hidden or grayed like be muted by user.
9. **unfollow_muted** - user stops follow another user's list of muted users.
10. **reset_blacklist** - Removes all users from user's list of blacklisted users.
11. **reset_following_list** - Removes all users from user's list of following users.
12. **reset_muted_list** - Removes all users from user's list of muted users.
13. **reset_follow_blacklist** - Removes all users from user's list of following another users blacklisted users.
14. **reset_follow_muted_list** - Removes all users from user's list of following another users muted users.
15. **reset_all_lists** - User will not follow, ignore or blacklist anyone, like new created user.

#### Follow Operation

To create follow operation, you need to user `custom_json_operation`. Field `id` have to be set to `follow`, in`required_posting_auths` you need to put `follower` name.
Field `json` have to be a list, first element must be a string value - `follow` and second has to be a json, which has to contains 3 keys:
- `follower` - user on which action will be performed.
- `following` - user on which another user will perform follow operation (when using one of resets action, this field is ignored, can be set to null or whatever). This field can be a string or a list. In case of list, specific follow action will be performed on every user from list.
- `what` - has to be a list and it has to contain one of follow actions. In case when we want to unfollow ir cancel ignore on specific user, list should be empty or we can action to empty string - `""` (be aware, removing user from blacklist needs `unblacklist` action)

Example follow operation:
```
{
  "type": "custom_json_operation",
  "value": {
    "required_auths": [],
    "required_posting_auths": [
      "user-follower"
    ],
    "id": "follow",
    "json": "[\"follow\",{\"follower\":\"user-follower\",\"following\":\"cool-user\",\"what\":[\"follow\"]}]"
  }
}
```

Example follow operation where user performs follow action on many users.
```
{
  "type": "custom_json_operation",
  "value": {
    "required_auths": [],
    "required_posting_auths": [
      "user-follower"
    ],
    "id": "follow",
    "json": "[\"follow\",{\"follower\":\"user-follower\",\"following\":[\"cool-user\",\"cleverguy\"]\"what\":[\"follow\"]}]"
  }
}
```

### Example Follow Operations

1. Follow user or users.

In this follow operation, user follows another user.

```
{
  "type": "custom_json_operation",
  "value": {
    "required_auths": [],
    "required_posting_auths": [
      "user-follower"
    ],
    "id": "follow",
    "json": "[\"follow\",{\"follower\":\"user-follower\",\"following\":\"cool-user\",\"what\":[\"blog\"]}]"
  }
}
```
If we want to set follow on multiple users in one operation, here is an example.

```
{
  "type": "custom_json_operation",
  "value": {
    "required_auths": [],
    "required_posting_auths": [
      "user-follower"
    ],
    "id": "follow",
    "json": "[\"follow\",{\"follower\":\"user-follower\",\"following\":[\"cool-user\", \"clever-guy\", \"info-bot\"],\"what\":[\"follow\"]}]"
  }
}
```

2. Ignore/mute user or users.

Example follow operation which mutes another user:

```
{
  "type": "custom_json_operation",
  "value": {
    "required_auths": [],
    "required_posting_auths": [
      "user-follower"
    ],
    "id": "follow",
    "json": "[\"follow\",{\"follower\":\"user-follower\",\"following\":\"spamer\",\"what\":[\"ignore\"]}]"
  }
}
```

3. Canceling follow or ignore from specific user.

```
{
  "type": "custom_json_operation",
  "value": {
    "required_auths": [],
    "required_posting_auths": [
      "user-follower"
    ],
    "id": "follow",
    "json": "[\"follow\",{\"follower\":\"user-follower\",\"following\":\"someone\",\"what\":[]}]"
  }
}
```

```
{
  "type": "custom_json_operation",
  "value": {
    "required_auths": [],
    "required_posting_auths": [
      "user-follower"
    ],
    "id": "follow",
    "json": "[\"follow\",{\"follower\":\"user-follower\",\"following\":\"someone\",\"what\":[\"\"]}]"
  }
}
```

4. Putting user on blacklist
```
{
  "type": "custom_json_operation",
  "value": {
    "required_auths": [],
    "required_posting_auths": [
      "user-follower"
    ],
    "id": "follow",
    "json": "[\"follow\",{\"follower\":\"user-follower\",\"following\":\"suspected-guy\",\"what\":[\"blacklist\"]}]"
  }
}
```

5. Removing user from blacklist

```
{
  "type": "custom_json_operation",
  "value": {
    "required_auths": [],
    "required_posting_auths": [
      "user-follower"
    ],
    "id": "follow",
    "json": "[\"follow\",{\"follower\":\"user-follower\",\"following\":\"good-guy\",\"what\":[\"unblacklist\"]}]"
  }
}
```

5. Following another user's list of blacklisted users

```
{
  "type": "custom_json_operation",
  "value": {
    "required_auths": [],
    "required_posting_auths": [
      "user-follower"
    ],
    "id": "follow",
    "json": "[\"follow\",{\"follower\":\"user-follower\",\"following\":\"guy-who-knowns\",\"what\":[\"follow_blacklist\"]}]"
  }
}
```

5. Stoping follow another user's list of blacklisted users

```
{
  "type": "custom_json_operation",
  "value": {
    "required_auths": [],
    "required_posting_auths": [
      "user-follower"
    ],
    "id": "follow",
    "json": "[\"follow\",{\"follower\":\"user-follower\",\"following\":\"guywithfakeinfo\",\"what\":[\"unfollow_blacklist\"]}]"
  }
}
```

6. Following another user's list of muted users

```
{
  "type": "custom_json_operation",
  "value": {
    "required_auths": [],
    "required_posting_auths": [
      "user-follower"
    ],
    "id": "follow",
    "json": "[\"follow\",{\"follower\":\"user-follower\",\"following\":\"guyignorescommunity\",\"what\":[\"follow_muted\"]}]"
  }
}
```

7. Stoping follow another user's list of muted users

```
{
  "type": "custom_json_operation",
  "value": {
    "required_auths": [],
    "required_posting_auths": [
      "user-follower"
    ],
    "id": "follow",
    "json": "[\"follow\",{\"follower\":\"user-follower\",\"following\":\"guywithfakeinfo\",\"what\":[\"unfollow_muted\"]}]"
  }
}
```

8. Reset user's list of blacklisted users

```
{
  "type": "custom_json_operation",
  "value": {
    "required_auths": [],
    "required_posting_auths": [
      "user-follower"
    ],
    "id": "follow",
    "json": "[\"follow\",{\"follower\":\"user-follower\",\"following\":\"\",\"what\":[\"reset_blacklist\"]}]"
  }
}
```

9. Reset user's list of following users

```
{
  "type": "custom_json_operation",
  "value": {
    "required_auths": [],
    "required_posting_auths": [
      "user-follower"
    ],
    "id": "follow",
    "json": "[\"follow\",{\"follower\":\"user-follower\",\"following\":\"!@#$%^&*()_\",\"what\":[\"reset_following_list\"]}]"
  }
}
```

10. Reset user's list of muted users

```
{
  "type": "custom_json_operation",
  "value": {
    "required_auths": [],
    "required_posting_auths": [
      "user-follower"
    ],
    "id": "follow",
    "json": "[\"follow\",{\"follower\":\"user-follower\",\"following\":[\"!@#$%^&*()_\"],\"what\":[\"reset_muted_list\"]}]"
  }
}
```

11. Reset user's list of following another users blacklisted users.

```
{
  "type": "custom_json_operation",
  "value": {
    "required_auths": [],
    "required_posting_auths": [
      "user-follower"
    ],
    "id": "follow",
    "json": "[\"follow\",{\"follower\":\"user-follower\",\"following\":[\"!@#$%^&*()_\", \"fdsafsadf\"],\"what\":[\"reset_follow_blacklist\"]}]"
  }
}
```

12. Reset user's list of following another users muted users.

```
{
  "type": "custom_json_operation",
  "value": {
    "required_auths": [],
    "required_posting_auths": [
      "user-follower"
    ],
    "id": "follow",
    "json": "[\"follow\",{\"follower\":\"user-follower\",\"following\":[],\"what\":[\"reset_follow_muted_list\"]}]"
  }
}
```

13. Clear user's all lists

```
{
  "type": "custom_json_operation",
  "value": {
    "required_auths": [],
    "required_posting_auths": [
      "user-follower"
    ],
    "id": "follow",
    "json": "[\"follow\",{\"follower\":\"user-follower\",\"following\":null,\"what\":[\"reset_all_lists\"]}]"
  }
}
```
