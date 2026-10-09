# Votes in bridge post calls

Every post object returned by `bridge.get_ranked_posts`, `bridge.get_account_posts`,
`bridge.get_post` and `bridge.get_discussion` embeds `active_votes`: up to 1000 votes,
ordered by voter account id. On popular posts that list is most of the response, and
on posts with more than 1000 votes it drops the newest accounts' votes, so a client
can't use it to tell whether the logged-in user voted.

Those calls are unchanged. The calls below are added next to them.

## Vote-free post calls

| Method | Same parameters and behaviour as |
|---|---|
| `bridge.get_ranked_posts_v2` | `bridge.get_ranked_posts` |
| `bridge.get_account_posts_v2` | `bridge.get_account_posts` |
| `bridge.get_post_v2` | `bridge.get_post` |
| `bridge.get_discussion_v2` | `bridge.get_discussion` |

Each accepts its counterpart's parameters plus `top_votes` (integer 0–10, default 0).
Each post object (every entry of a list or discussion) differs from the counterpart's
in exactly these ways:

- `active_votes` is absent (not `[]`).
- `observer_vote` is `{"rshares": <int>, "percent": <int>}` when `observer` is given
  and has voted on the post, `null` otherwise. It is looked up directly, so it is
  correct on posts of any size. A removed vote reads `{"rshares": 0, "percent": 0}`.
- `top_votes`, only when `top_votes` > 0: up to that many
  `{"voter", "rshares", "percent"}` entries with the largest `|rshares|` first
  (ties by voter account id), leaving out voters the observer muted.
- `stats.total_votes` remains the vote count.

```json
{"jsonrpc": "2.0", "id": 1, "method": "bridge.get_post_v2",
 "params": {"author": "gtg", "permlink": "heavy-duty-witness-node-infrastructure", "observer": "alice", "top_votes": 3}}
```

## `bridge.list_votes`

Pages through a post's votes.

| Parameter | |
|---|---|
| `author`, `permlink` | required |
| `start` | voter name; the page starts after this voter (optional) |
| `limit` | 1–1000, default 100 |
| `observer` | optional; leaves out voters the observer muted |

The result is an array of `{"voter", "rshares", "percent", "weight", "time", "reputation"}`
ordered by voter account id (`reputation` is the log10 score, as in other bridge
objects). Pass the last returned `voter` as `start` to get the next page. Each voter
appears once across pages, and an empty array means there are no more votes.

## Migrating a front end

Switch feed, profile and post requests to the `*_v2` methods and read `observer_vote`
to show whether the logged-in user voted. Request `top_votes` when cards show a few
voters, and use `bridge.list_votes` where the full voter list is shown. Nodes running
an older hivemind answer the new methods with an unknown-method error. When that
happens, call the old method and read `active_votes`.
