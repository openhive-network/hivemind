# Massive sync gives the same data at any batch size (#477)

The README's "Data and crash replay" section found that the synced data depended on the batch size and on
where batches started: a batch applied all its posts before all its votes and folded each voter's votes, a
post's mentions were taken once per batch, and a replayed batch applied its comment ops a second time. #477
makes massive sync produce what processing the same blocks one at a time produces, which is also what live
sync does with each block.

## What one block at a time gives, and what a batch now does

| | one block at a time | the batch SQL now |
|---|---|---|
| a vote on a post deleted later | the vote's block finds the post live: the vote is kept, on the deleted version | each block's votes resolve the version live at the end of that block (created by then, deleted after it: a deleted version's `block_num` is its delete block); a vote whose block ends with no live version is dropped |
| a vote cast before a delete and re-create | stays on the old version unless the voter votes again after the re-create | the same rule; the last block's version wins |
| `num_changes` | every block after the first adds `GREATEST(effective votes, 1)`, also a block whose vote has no `effective_comment_vote` (46,380 such voter-post-blocks in the 5M fixture) | votes are folded per (voter, post, block) first, then `sum(GREATEST(effective votes, 1)) - 1` per voter and post; the replay guard is unchanged |
| `is_effective` | taken from the first block's insert, never updated | the insert takes the first block's flag; the weight and rshares still come from the last effective block |
| payouts | each block updates the version live at its end; `author_rewards` adds each block's comment reward; pending payout and vote weight are the last block's | resolved and folded per block the same way |
| `active` of a post edited in a later block | set by the edit's `ON CONFLICT` path | Step 5c sets it with `updated_at` |
| mention notifications | one per block whose body mentions the account, keyed on that block; a block whose body no longer mentions it deletes the account's mention notifications and `hive_mentions` row for the post; a block ending with the post deleted mentions nobody; only accounts existing by then | `PostDataCache` keeps each post's body at the end of every block it had an op in, and `process_hive_post_mentions` applies those snapshots set-based with the same rules |
| replaying a batch whose posts phase committed | (live sync commits each block atomically) | the posts phase saves its results with a marker in the same transaction (`_batch_post_results`, `_batch_queue.posts_applied`); a replay reuses them instead of applying the comment ops again; the post data flush commits its own marker (`post_data_applied`) and a replay skips it |

## Results

HAF 5M fixture on steem-4, set up as in the README (blocks 0–4,990,000, reptracker synced first, no mocks),
in `/scratch/hm477`: a copy of this directory's `pg.sh` and `install.sh` with `hm470` renamed. Each run is a
ZFS clone of one installed snapshot (`fidelity_run.sh`); `fidelity_dump.sql` dumps posts (all versions), votes,
notifications, `hive_mentions` and post data on natural keys, and `fidelity_compare.py` diffs two runs after
dropping surrogate ids drawn in processing order (`permlink_id`, `category_id`). The 1000 and 10000 runs
below ran the final code; the one-block reference and the crash runs ran earlier revisions of it whose mention
statement looked reputations up through a CTE (the first crash run also before mentions checked that the
account existed). Each was compared with runs of its own revision, and the final code's 10000-block run is
identical to the earlier revision's.

| | base 1000 | base 10000 | #477 1000 | #477 10000 |
|---|---|---|---|---|
| votes | 4,391,192 | 4,390,830 | 4,391,751 | 4,391,751 |
| votes on deleted posts | 2,734 | 2,372 | 3,293 | 3,293 |
| sum of `num_changes` | 48,044 | 47,657 | 80,363 | 80,363 |
| mention notifications | 158,236 | 135,244 | 216,322 | 216,313 |
| `hive_mentions` | 128,573 | 128,500 | 129,003 | 129,003 |
| notifications | 2,059,454 | 2,036,379 | 2,117,560 | 2,117,573 |

With #477, 1000 and 10000 blocks per batch give identical `hive_posts` (957,031 rows with every deleted
version), `hive_votes` including `num_changes`, `hive_mentions` and post data. In the base pair, 34,281 post
rows, 613 and 251 vote rows, 12,219 and 12,146 `hive_mentions` rows and 23,889 and 814 notifications are in
only one of the two runs.

**One block at a time.** A sync at 10000 killed in batch 4,490,001–4,500,000 and restarted to 4,510,000
with `--max-batch=1` replayed that batch and then ran 10,000 one-block batches; the same restart with
10000-block batches ran one batch. Posts, votes, notifications, `hive_mentions` and post data are identical.

**Crash replay.** A 10000-block run killed right after the posts phase of batch 4,500,001–4,510,000 committed
(`posts_applied`, flush not yet), and one killed after the posts phase and the post data flush of batch
4,730,001–4,740,000 had committed, both replayed and finished with data identical to the uninterrupted run:
no extra post versions, no missing notifications. The base code's replay left 62 extra deleted versions and
3,784 fewer notifications (README).

**What still differs: mutes.** Notifications differ in 52 of 2.12 M rows at 1000 and 65 at 10000 (reply,
reblog, follow and mention notifications, types 12–16), the same rows as in the base pair for types 12–15.
Every notification writer filters through `muted` and `follow_muted` as they are at the end of the batch,
where one block at a time sees them at the end of the notification's block. For example sokoloffa muted
msjennifer at block 3,588,549, unmuted at 3,589,010, muted at 3,590,194 and unmuted at 3,599,455: the replies
at 3,588,541 and 3,590,190 get notifications from one-block processing and the 10000-block batch, and none
from the 1000-block batch, which ends while the mute holds. Fixing it means recording each batch's mute
history in the follow processing that live sync shares; #477 leaves it ([#482](#mutes-ids-and-reblogs-482)
fixes it; one of the rows is a reblog fold, not a mute).

## Tavern patterns

The tavern patterns were generated from a CI sync at 1000 blocks per batch, so they carry its boundary
effects. On a fixture synced by this change at 10000 blocks (template `cedc3f8b5608`), 72 pattern tests (and 25
`rest_api_equivalence` tests derived from them) differed and were refreshed from that fixture's output. Spot
checks against the raw operations confirm the new values are what one block at a time gives: nession's vote on
xeroc's piston post has two vote blocks and no effective vote, `num_changes` 1 (the pattern's 0 folded both into
one 1000-block batch); dantheman's reply to calaber24p keeps the `total_vote_weight` of its last effective vote
(a comment reward in the same 1000-block batch had discarded it). The other differences are mention duplicates
per edit block, unread counts that follow from them, payout totals, and lists ordered by post or notification
id: inside a batch, root posts take ids before comments and re-created posts after both, so id order still
follows batch boundaries (#470's base fixture differed from the patterns in those lists too; #482 removes it).

## Cost

Massive phase sums over 0–4.99M, runs sharing the host with each other (advisory):

| | base 1000 | #477 1000 | base 10000 | #477 10000 |
|---|---|---|---|---|
| all phases | 709 s | 794 s | 542 s | 545 s |
| posts (saving the results for a replay) | 194 s | 190 s | 164 s | 166 s |
| votes (folding per block) | 93 s | 112 s | 70 s | 77 s |
| flush (per-block mentions) | 113 s | 137 s | 74 s | 79 s |
| parallel (payouts beside reblogs and follows) | 133 s | 185 s | 104 s | 100 s |

The payouts statement takes about 1.0 s of a 10000-block batch in 3.4–3.5M (block-level aggregation 0.3 s,
version lookup 0.2 s, fold and update 0.5 s), linear in the batch's payout ops. It runs beside reblogs and
follows: at 10000 blocks the parallel phase's sum did not change, at 1000 it grew by 52 s (10 ms a batch). A first version of the mention statement joined a CTE
of the authors' reputations back to the rows; on a 1-row estimate it was rescanned per row (12.6 s for 3,386
mentions in one batch, flush 701 s in all). The reputation is now looked up per row, as
`flush_post_notifications_for_blocks` does.

## Mutes, ids and reblogs (#482)

#477 left two dependences on the batch size, and the 52/65 notification rows it attributed to mutes held a third.

| | one block at a time | the batch SQL now |
|---|---|---|
| post ids | (a one-block batch drew them roots first, then comment waves, then re-creates, and an edit drew an id through `ON CONFLICT`) | each comment op of a batch owns one id, reserved in operation order (`reserve_post_ids`): the op ranked k among the batch's comment ops owns base + k, whether it inserts a post or not. A post's id is its op's rank among the chain's comment ops at any batch size; live sync runs the same function per block. The base is `_post_id_slots` (LOGGED), updated in the posts phase's transaction, so a replay of a batch whose posts phase rolled back reserves the same ids |
| reply (12/13) notification ids | counter: the post's rank among the block's new comments by id | the same; it follows the ids |
| muted-post error (10) ids | counter: the op's `seq_id`, its rank among the block's comment ops | the op's rank among its block's comment ops (was its `seq_id` in the batch) |
| mention (16) ids | counter: rank among the block's mentions by (account, post) | ranked among all the block's mention snapshots, also those a later block of the batch drops (was: among the final runs only) |
| vote (17) ids | counter: rank by `hive_votes.id` in the vote's last block | `hive_votes` ids are drawn in (first block, voter, author, permlink) order, so any two rows' ids are in the same order at any batch size (their gaps still differ) |
| mute filter | `muted`/`follow_muted` at the end of the notification's block | `process_follows_for_blocks` records the batch's changes of both lists in `_batch_mute_changes` (LOGGED): per pair on a list at some point, its state before the phase and after each change, a reset as a change of every pair the phase knows of. The reply, reblog, follow and mention writers keep their joins unless the batch changed a list their filter reads for that pair; then `notification_muted_at` applies the same filter to the lists at the end of the notification's block. `_batch_queue.follows_applied` commits with the follows phase, and a replay after it keeps the recorded changes |
| repeated reblog | the first reblog inserts the row (and its notification); a later one finds it | the row comes from the first reblog after the batch's last unreblog (was: the batch's last reblog). jamesc reblogged dantheman's why-do-we-fight-to-change-the-world at 4,594,648 and again at 4,596,441: the 10000-block batch dated the row and its notification at 4,596,441 |

Same fixture and scripts as above, in `/scratch/hm482` on steem-4 (`fidelity_run.sh` and
`fidelity_one_block.sh` with `hm477` paths renamed, every run a clone of `scratch/hm477-base@installed`).
`fidelity_dump.sql` now also dumps the ids as drawn (`post_ids.txt`: id, natural key, parent and root ids;
`notif_ids.txt`: every notification row with its id and post ids).

| compared | posts, votes, mentions, post data | notifications | post ids | notification ids |
|---|---|---|---|---|
| base 1000 / base 10000 | identical | 52 / 65 rows (types 12–16) | 956,949 of 957,031 differ | 1,693,534 / 1,693,547 rows |
| base 10000 / #482 10000 | identical | 65 / 87 rows: the mute filter (types 12, 13, 15, 16) and the reblog row (14) | 957,017 differ | (follow the post ids) |
| #482 1000 / #482 10000 | identical | identical | identical | identical |
| #482: 4,500,001–4,510,000 one block at a time / one batch | identical | identical | identical | identical |
| #482 10000 / killed after batch 4,590,001–4,600,000's follows and posts phases committed, replayed | identical | identical | identical | identical |

The one-block run is `fidelity_one_block.sh`: a 10000-block sync killed in batch 4,490,001–4,500,000 and
restarted to 4,510,000 with `--max-batch=1` (10,450 batches), against the same restart at 10000. The crash run
waited for `_batch_queue.follows_applied` and killed the sync with the post data flush and the notifications of
that batch still to run. An earlier revision of this change (the same id and mute rules, the reblog fold not
yet fixed) also gave identical data and ids after a kill before a batch's posts phase committed (4,710,001–4,720,000),
and identical 1000/10000 runs but for the reblog row above.

**Spot checks.** sokoloffa muted msjennifer at 3,588,549 and unmuted at 3,589,010: msjennifer's reply at
3,588,994 has a notification in the base 10000 run (the batch ends unmuted) and in none of #482's runs. HAF's
operations up to 4,990,000 hold the two jamesc reblogs of that post and no unreblog between them.

**Not covered.** A reblog, unreblog and reblog of one post by one account inside a batch still gives one row
and one notification (one block at a time: a notification for each reblog), and a reblog of a post deleted
later in the batch resolves the post at the end of the batch; neither occurs in the 5M fixture. Vote
notifications are written at finalization at any batch size, from the lists as they stand then.

**Tavern** has not run on a fixture synced by this change: the shared fixture is seeded from a pushed commit,
and the runs above have no mocks. The patterns that can move are those holding post or notification ids (few
patterns show a post id; 29 notification patterns show notification ids), lists ordered or paged by them, and
reblog dates; each is to be checked against one block at a time, as #477's refresh was.

**Existing nodes** keep the ids their sync gave; the first batch after the upgrade reserves ids after the
sequence's last value, so later posts sort after them. A rebuild gives every post its op's id.

**Cost.** Massive phase sums over 0–4.99M, the runs sharing the host (advisory):

| | base 1000 | #482 1000 | base 10000 | #482 10000 |
|---|---|---|---|---|
| all phases | 848 s | 855 s | 584 s | 581 s |
| posts (reserving the ids) | 209 s | 210 s | 183 s | 180 s |
| parallel (follows recording the mute changes) | 220 s | 224 s | 126 s | 125 s |
| notify (the per-block mute filter) | 41 s | 46 s | 31 s | 34 s |

A first version filtered each candidate notification through a SQL function holding
subqueries, which PostgreSQL does not inline: about 10 µs a row, notify 39.5 s. The writers now join the
accounts the batch's mute changes touch, and call `notification_muted_at` only for those rows.

## Tavern on #482's data, checked one block at a time (#484)

The tavern fixture (HAF 5M, CI's mocks, a sync to 5,000,024 with `--community-start-block 4998000`) synced
by #482's code (shared template `f8835692220e`) failed 21 condenser, 34 bridge, 4 REST and 30 REST-equivalence
tests. Runs on steem-18, each a database cloned from one install as `.aidev/shared-hivemind/seed.sh` makes it:
the default sync (10000 blocks a batch; the 45 blocks past HAF's irreversible head, 4,999,980–5,000,024, run
live, one at a time, in every run) and the same sync killed in batch 4,950,001–4,960,000 and restarted with
`--max-batch=1` (39,979 one-block batches to 4,999,979). `fidelity_dump.sql` dumps both.

**Mock order.** The mocker loaded `mock_data/**/*.json` in directory order, and 22 blocks
(4,998,001–4,998,014, 4,999,999, 5,000,010–5,000,021) take ops from several files, so the account, post and
notification ids of the mocks depended on the filesystem: a checkout on steem-18's tmpfs put the reblog mocks
before the community ones and gave other ids than the shared template. It now loads them in path order. On
every multi-file block that is the order the seeder's checkout had: with it the default sync gives the
template's data exactly (every `hivemind_app` table but the install timestamps and `hive_mentions.id`).

**Checks of the refreshed values.**
- Post ids: on the template, for all 961,423 posts the comment op ranked `id` among HAF's 1,258,142 comment
  ops up to 5,000,024 is a comment by the post's author and permlink in its creation block.
- Lists ordered by post id (`created`, comments, replies and their paging) hold posts in chain order: no
  refreshed one has a `created` inversion, the old patterns 1–2 each. Apart from the reblog counts below, no
  post common to an old and a new pattern changed a value; posts left or entered pages and pages reordered.
- Reply notification ids: the 18 changed ids (gtg, dantheman, test-safari, steve-walschot, venuspcs) carry the
  reply's rank among its block's new replies in HAF operation order (the old ids, roots first, did not).
  `post_notifications/account_permlink_last_it_votes` pages from `last_id` 3267314820579330, which is now the
  mafia reply's own id, so the page starts after it.
- One block at a time: the restarted run gives the default run's posts, votes, mentions, post data and post
  ids, and serves every refreshed value; the one refreshed pattern failing on it,
  `account_notifications/test-safari`, differs only in community notifications the refresh left as they were.

**Reblogs of a post before it exists.** One block at a time a reblog resolves the post version live at the end
of its block, and finds nothing before the post is created. The batch resolved every reblog at the end of the
batch: funny's reblog of dollarvigilante's post (4,998,001, the post is created at 4,998,413) and
test-reblog-03's of test-creator/reblogged-post (4,998,003, created at 4,998,008) became rows, notifications
and feed entries. `process_reblogs_from_staging` now drops the ops of blocks before the live version was
created; 36 reblogs became 34, as one block at a time, and 26 tavern patterns (and 2 search-api ones) take the
one-block values: `reblogs` counts, funny's blog and the feeds that showed the reblog, and the counter of
funny's reblog notification of steemit/firstpost in the same block.

**Still different one block at a time** (values this refresh leaves as they were; 17 bridge tests and 3
REST twins fail on the one-block run):
- reblog notifications of rows the batch never keeps: a reblog undone later in the batch (test-116, 4 rows)
  and reblogs of a version deleted later in the batch (monkey-02, monkey-04, parrot-04, 4 rows), which one block
  at a time notifies; `unread_notifications` abit and min_score count them;
- community ops: moderation log and moderator activity entries (ids and rows), test-safari's community
  notifications (score 35 in the batch, 15 one block at a time), two muted-post errors and
  blocktrades/elephant01#1's `is_muted`.

## Ids are internal: compare natural keys (#519)

Hivemind's surrogate ids (post, permlink, category, vote, reblog, mention and notification ids) are internal.
A resumed sync or a pipelined one (`--massive-sync-pipelined`) may draw them in another order than a sequential
sync of the same blocks, and that is not a difference: two runs have the same data when their rows match on
natural keys. On steem-19, the #500 kill-a and kill-f runs differed only in `votes.txt` (`permlink_id`, in
110,392,000 rows), `reblogs.txt` (the reblog id, in 1,082,962 rows) and `counts.txt` (`max_reblog_id`,
7,052,744 against 7,056,265).

`fidelity_dump.sql` now keys and prints every row by account names, permlinks, categories, community names,
the post key (`author/permlink#counter_deleted`) and block numbers, and no id column survives in any file:

| file | ids replaced or dropped |
|---|---|
| `posts.txt` | `parent_id`, `root_id` by their post keys; `category_id` by the category, `community_id` by the community name; `author_id` and `permlink_id` are in the key |
| `votes.txt` | `voter_id`, `author_id` and `permlink_id` dropped (the key is voter>permlink@author), `post_id` by its post key |
| `notifs.txt` | `src` and `dst` by account names, `post_id` and `dst_post_id` by post keys, the notification id dropped |
| `mentions.txt` | `account_id` by the account name |
| `accounts.txt` | the id dropped from the row JSON |
| `reblogs.txt` | the reblog id dropped; ordered by blogger, post key and block number |
| `counts.txt` | `max_reblog_id` dropped; the `reblogs` count stays |

`post_ids.txt` and `notif_ids.txt` still show the post and notification ids as drawn, for checking the id rules
of #482. They are informational: `fidelity_compare.py` reports them after the compared files and leaves them out
of its verdict. It no longer strips `permlink_id` and `category_id` from the lines (the dumps carry none), prints
`IDENTICAL` or `DIFFERENT:` with the counts and files that differ, and exits 1 on a difference. Dumps written
by an earlier `fidelity_dump.sql` are to be dumped again before comparing.

**Check.** Two scratch databases with the same posts, votes, reblogs, mentions, notifications and follows, one
drawing every id in reverse order: the earlier dump differs in `posts`, `votes` and `reblogs` (the steem-19
differences in miniature), this one is identical in every compared file, with `post_ids` and `notif_ids`
reported as differing. A vote weight changed from 100 to 101 in one copy, and a reblog moved to another post,
show as one line each in `votes` and `reblogs`, and the verdict is `DIFFERENT: votes, reblogs`. This check has
not been run on two fixture syncs.
