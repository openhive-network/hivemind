# Hive Communities Design

## Introduction

Before the introduction of communities, Most Hive frontends used to rely on the global tags system for organization.
In this sense Hive had many "communities" already but they were entirely informal; there was no ownership and no ability to formally organize.
Tag usage standards are not possible to enforce, and users have different goals as to what they want to see and what sort of communities they want each tag to embody. 

Hive communities add a governance layer which allows users to organize around a set of values, and gives them the power to do so effectively.
It introduces a new system of moderation which is not dependent on users' hive power.
By making it easier to organize, this system can be far more effective at connecting creators and curators.
Curators are be attracted to communities which are well-organized: focused, high-quality, low-noise. Making it easier to find the highest quality content will make it easier to reward high quality content.

Many people want to see long-form, original content while many others just want to share links and snippets.
The goal of the community feature is to empower users to create tighter groups and focus on what's important to them. 

Use cases for communities include:
 - microblogging & curated journals
 - local meetups
 - link sharing
 - world news
 - curation guilds (cross-posting undervalued posts, overvalued posts, plagiarism, etc)
 - original photography
 - funny youtube videos
 - etc

Communities are not a blockchain level feature, they exist within the hivemind set of APIs. 
This means that if a user is forbidden from posting, they can still post to the community. 
the difference is that the post will be tagged as "hidden" in api responses. (and front ends will not display it, but are free to do so!) 

## Overview

#### Community Types

By default, communities are open for all to post and comment ("topics" or type 1). 
However, an organization may create a restricted community ("journal" or type 2) for official updates: only members of the organization would be able to publish posts, but anyone can comment. 
Alternatively, a professional group or local community ("council" or type 3) may choose to limit all posting and commenting to approved members (perhaps those they verify independently).

1. **Topic / type 1**: anyone can post or comment
2. **Journal / type 2**: guests can comment but not post. only members can post.
3. **Council / type 3**: only members can post or comment

#### User Roles Overview

1. **Owner**: can assign admins. 
2. **Admin**: can edit community properties and assign mods.
3. **Mod**: can mute posts/users, add/remove members, pin/unpin posts, set user titles/roles.
4. **Member**: in restricted (journal/council) communities, an approved member.
5. **Guest**: can post/comment in topics and comment in journals.
6. **Muted**: forbidden from posting or commenting. 

#### User Actions

Each role includes all the privileges of roles below it in the hierarchy.

**Owner** has the ability to:

- **set admins**: assign or revoke admin privileges

**Admins** have the ability to:

- **set moderators**: grant or revoke mod privileges
- **set community properties**: Update community properties (title/rules/description/NSFW/etc...)
- **set community type**: Update community to topic, journal or council 

**Moderators** have the ability to:

- **set user roles:** member, guest, muted
- **set user titles**: ability to add a label for specific users, designating role or status
- **mute posts**: prevents the post from being shown in the UI (until unmuted)
- **pin posts**: ability for specific posts to always show at the top of the community feed

**Members** have the ability to:

- **in an topic**: N/A (no special abilities)
- **in a journal: post** (where guests can only comment)
- **in a council: post and comment** (where guests cannot)

**Guests** have the ability to:

- **post in a topic**: as long as they are not muted
- **comment in a topic or journal**: as long as they are not muted
- **flag a post**: adds an item and a note to the community's moderation queue for review
- **subscribe to a community**: to customize their feed with communities they care about

**Muted** have no abilities and see their posts/comments hidden automatically

## Registration

##### NCI: Numerical Community Identifier

Communities are registered by creating an on-chain account which conforms to `/^hive-[1-3]\d{4,6}$/`, with the first digit signifying the *type*.
Type mappings are outlined in a later section. Thus the valid range is  `hive-10000` to `hive-3999999` for a total of 1M possible communities per type. This ensures the core protocol has stable ids for linking data without introducing a naming system.

Do note that the numerical system only defines what type the community will be created as. An admin can later change the type. (eg: if a community grows big enough to prevent guests from posting)

##### Custom URLs

Name registration, particularly in decentralized systems, is far from trivial. The ideal properties for registering community URLs include:

1. ability to claim a custom URL based on a subjective capacity to lead that community
2. ability to reassign a URL which has ceased activity (due to lost key or inactivity)
3. ability to reassign a URL due to trademark issues
4. decentralization: no central entity is controlling registration or collecting payments

Name reassignments result unpredictable and/or complex behavior, which is why internal identifiers are not human-readable.
This approach does not preclude anyone from developing a standardized naming system. 
Such a system may be objective and automated or subjective and voting driven.
For subjective approaches, starting with just a numerical id is particularly useful as it allows a community to demonstrate its prowess before making a case to claim a specific human-readable identifier.

At the moment custom URLs are not implemented.

## Considerations

- Operations such as role grants and mutes are not retroactive.
  - This is to allow for consistent state among services which can also be replayed independently, as well as for simplicity of implementation. If it is needed to batch-mute old posts, this can be still be accomplished by issuing batch `mutePost` operations.
  - Example: If a user is muted, the state of their previous posts is not changed. If the user attempts to post in a community during this period (e.g. from a UI which does not properly enforce roles), their posts will be marked "invalid" since they did not have the correct privilege at the time. Likewise, if they are unmuted, any of these "invalid" posts remain so.
- A post's `community` cannot be changed after the post is created. This avoids a host of edge cases.
- A community can only have one account named as the owner.
- Each user in a community is assigned, at most, 1 role (admin, mod, member, guest, muted).

## Community Metadata

##### Editable by Admins - Community Properties

Can be stored as a JSON dictionary.

 - `title`: the display name of this community (32 chars)
 - `about`: short blurb about this community (120 chars)
 - `lang`: primary language. `en`, `es`, `ru`, etc (https://en.wikipedia.org/wiki/ISO_639-3 ?)
 - `is_nsfw`: `true` if this community is 18+. UI to automatically tag all posts/comments `nsfw`
 - `description`: a blob of markdown to describe purpose, enumerate rules, etc. (5000 chars)
 - `flag_text`: custom text for reporting content
 - `settings': json dict; recognized keys:
   - `avatar_url` - same format as account avatars; usually rendered as a circle
 - `type_id`: change the type of the community (1,2 or 3)

Extra settings can be set arbitrary depending on one's need but those won't be validated.

## Creation

Creation an onchain account name which conforms to `/hive-[1-3]\d{4,6}$/` (eg: hive-111111) This is the owner account. From this account, submit a `setRole` command to set the first admin.

- Topics: the leading digit must be `1`
- Journals: the leading digit must be `2`
- Councils: the leading digit must be `3` 

## Operations

Communities are not part of blockchain consensus, so all operations take the form of `custom_json` operations which are to be monitored and validated by separate services to build and maintain state.

The standard format for `custom_json` ops:

```
{
  required_auths: [],
  required_posting_auths: [<account>],
  id: "community",
  json: [
    <action>, 
    {
      community: <community>, 
      <params*>
    }
  ]
}
```

 - `<account>` is the account submitting the `custom_json` operation.  
 - `<action>` is a string which names a valid action, outlined below.
 - `<community>` required parameter for all ops and names a valid community.  
 - `<params*>` is any number of other parameters for the action being performed

### Setting Roles

```
["setRole", {
    "community": <community>,
    "account": <account>,
    "role": admin|mod|member|none|muted,
    "notes": <comment>
}]
```

*Owner* can set any role.

*Admins* can set the role of any account to any level below `admin`, except for other *Admins*.

*Mods* can set the role of any account to any level below `mod`, except for other *Mods*.

### Admin Operations

In addition to editing user roles (e.g. appointing mods), admins can define the reward share and control display settings.

#### Update settings

```
["updateProps", {
  "community": <community>, 
  "props": { <key:value>, ... }
}]
```

Validated keys are `title`, `about`, `lang`, `is_nsfw`, `description`, `flag_text`, `settings`, `type_id`, `avatar_url`.

but you are free to add any extra settings you want.

### Moderator Operations

In addition to editing user roles (e.g., approving a member or muting a user), mods have the ability to set user titles, mute posts, and pin posts.

#### Set user title

```
["setUserTitle", {
  "community": <community>,
  "account": <account>,
  "title": <title>
}]
```

#### Mute/unmute a post

Can be a topic or a comment.

```
["mutePost", {
  "community": <community>,
  "account": <account>,
  "permlink": <permlink>
  "notes": <comment>
}]
```

```
["unmutePost", {
  "community": <community>,
  "account": <account>,
  "permlink": <permlink>,
  "notes": <comment>
}]
```

#### Pin/unpin a post

Stickies a post to the top of the community homepage. If multiple posts are stickied, the newest ones are shown first.

```
["pinPost", {
  "community": <community>,
  "account": <account>,
  "permlink": <permlink>
}]
```


```
["unpinPost", {
  "community": <community>,
  "account": <account>,
  "permlink": <permlink>
}]
```

### Guest Operations

#### Un/subscribe to a community

Allows a user to signify which communities they want shown on their personal trending feed and to be shown in their navigation menu.

```
["subscribe", {
  "community": <community>
}]
```

```
["unsubscribe", {
  "community": <community>
}]
```

#### Flag a post

Raises awareness on a post/comment by sending it as a notification to team members (moderators included). It's up to the community to define what constitutes flagging.

```
["flagPost", {
  "community": <community>,
  "account": <account>,
  "permlink": <permlink>,
  "comment": <comment>
}]
```

#### Posting in a community

To mark a post as belonging to a community, the main tag (category) should be the name of the community. 

```
{
    "app": "hiveblog/0.1",
    "format": "html",
    "tags": ["hive-192921", "travel", "vlog"],
    [...]
}
```

If a post is edited to name a different community, this change will be ignored.
If a post is posted "into" a community which does not exist, the post will be published on the user's main blog. 
If the user does not have permission to post into the community, the post will be set as muted automatically

---

## Appendix C. Reference

1. Stratos subapp: Communities

   https://github.com/stratos-steem/stratos/wiki/Subapp:-Communities

## Appendix D. Communities creation flow

Creating a community is as simple as creating an account with the correct account name see [registration](#registration)
but if you are creating an UI, it might make sense to include extra calls to fully customize the community in the same window.

You mostly want to do those two calls, we'll take for example a community named: hive-135485
- 
### 1: set creator as admin:

Set the creator account as admin, it will be an easier UX for him because he won't have to log into the community account
```json
{
  "type": "custom_json_operation",
  "value": {
    "required_auths": [],
    "required_posting_auths": [
      "hive-135485"
    ],
    "id": "community",
    "json": "[\"setRole\",{\"community\":\"hive-135485\",\"account\":\"creatoraccount\",\"role\":\"admin\"}]"
  }
}
```

### 2: set the community details:

set the community various settings.
```json
{
  "type": "custom_json_operation",
  "value": {
    "required_auths": [],
    "required_posting_auths": [
      "creatoraccount"
    ],
    "id": "community",
    "json": "[\"updateProps\", {\"community\": \"hive-135485\", \"props\": {\"title\": \"World News\", \"about\": \"A place for major news from around the world.\", \"lang\": \"en\", \"is_nsfw\": false, \"description\": \"Welcome to World News. Here you can find major news updates from all around the globe. Please follow the rules and keep discussions respectful.\", \"flag_text\": \"Report inappropriate content.\", \"settings\": {\"avatar_url\": \"https://example.com/avatar.png\"}}}]"
  }
}
```
