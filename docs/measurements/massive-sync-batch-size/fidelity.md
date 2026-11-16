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
history in the follow processing that live sync shares; #477 leaves it.

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
follows batch boundaries (#470's base fixture differed from the patterns in those lists too).

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
