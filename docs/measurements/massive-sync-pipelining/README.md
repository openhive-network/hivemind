# Can massive sync pipeline its batches? (#498)

Massive sync runs each batch's phases one after another (`Blocks.process_multi_sql`, `hive/indexer/blocks.py`).
The question is whether Stage A of batch N+1 (load, accounts/communities, posts, community post ops) can run
while Stage B of batch N (votes, rshares, Phase 4, account updates, flush, notifications, vacuum) runs, and
what that would save.

**Answer.** Yes, but not as the phases are written today. Votes and payouts are already insensitive to the
next batch's posts phase. Six other places are not: reblogs, the post-delete cascade, `post_count`, the body
merge, the follows' and notifications' reads of the HAF context views, and the one-row `_batch_queue`. Each
has a bounded fix, listed below. Only two staging tables are read by both stages, so only those need a second
set, not every staging table.

On the 2026-11-20 rebuild's own per-batch times, a perfect two-stage pipeline would take the massive sync
from 19.03 h to 11.06 h (−42 %, after removing #495's stalls) and 10–30 M from 6.90 h to 3.95 h. The 25 %
target holds only while running both stages at once slows each by no more than about 1.27–1.32×. That
slowdown is not measured, and the prototype, the 10–30 M timing and the result comparison were not run here
(see the last section).

## Estimate from the 2026-11-20 rebuild

`data/phase_summary_20261120.csv` holds every `[PHASE-SUMMARY]` line (11,194 batches, blocks 1–111,840,322)
of `haf-hivemind-block-processing-1` on steem-20, read from its container log on 2026-11-20. Its phase shares
are the issue's (posts 35.9 %, votes 26.3 %, parallel 18.6 %, load 8.1 %, …; sum 69,614 s). `simulate.py`
replays them as a two-stage flow shop with two handoff sets:
- batch i's Stage A starts when batch i−1's Stage A has ended and batch i−2's Stage B has freed its set;
- batch i's Stage B starts when its own Stage A and batch i−1's Stage B have ended.

A uniform slowdown factor stands in for contention. Stage A = load + accounts_community + posts +
community_post. Stage B = everything else, including cache_merge, which the design moves to Stage B.
`--no-stalls` cuts #495's votes stalls (1,110 s; the issue quotes 1,104 s).

| range (stalls removed) | sequential | A / B sums | perfect overlap | slow 1.15 | slow 1.30 | slow 1.50 |
|---|---|---|---|---|---|---|
| all | 19.03 h, 1,633 blocks/s | 8.75 / 10.28 h | 11.06 h (−41.9 %) | 12.72 h (−33.1 %) | 14.38 h (−24.4 %) | 16.59 h (−12.8 %) |
| 10–30 M | 6.90 h, 805 blocks/s | 3.52 / 3.38 h | 3.95 h (−42.8 %) | 4.54 h (−34.2 %) | 5.13 h (−25.6 %) | 5.92 h (−14.2 %) |
| 30 M+ | 11.72 h | 5.04 / 6.68 h | 6.88 h (−41.3 %) | 7.91 h (−32.5 %) | 8.95 h (−23.7 %) | 10.32 h (−11.9 %) |

With the stalls left in, the whole sync goes from 19.34 h to 11.37 h (−41.2 %). The two stages are close to
balanced in every range: Stage A is the heavier one in 788 of the 2,001 batches of 10–30 M and in 545 of the
8,191 after 30 M. That balance is why perfect overlap gets near the 50 % ceiling, and also why any slowdown
costs it directly. A batch's time becomes max(A, B), so a 1.3× slowdown of both stages gives back two thirds
of the gain.

What sets the slowdown, to be measured:
- Both stages read and write `hive_posts` heavily (Stage A inserts and updates; Stage B's version lookups of
  votes and payouts, and the payout update).
- Stage B already runs 4 upsert connections in votes and 3 in Phase 4.
- The CPU was 50–60 % idle and IO wait 2–5 %, so there is headroom, but buffer and lock contention on
  `hive_posts` and its unique index are the unknown.

## 1. Independence of the two stages

### Votes of N against posts of N+1

`prepare_votes_from_staging` (massive_sync.sql:570) resolves each vote's post in Step 2 with a single
statement (`pair_version` … `INSERT INTO _vote_upsert`, :652–718). Under READ COMMITTED a single statement sees
one snapshot, so it either sees all of N+1's committed posts phase or none of it. Both give the same result:
- **Delete in N+1.** The delete sets `counter_deleted > 0` and `block_num` to the delete block (:1737), so
  `deleted_block > vb.block_num` (:681) keeps the vote on that version.
- **Re-create in N+1.** The new row has `block_num_created` > every vote of N and is excluded.
- **Edit in N+1.** An edit sets `block_num` only on a live row (:1571), whose `deleted_block` is NULL.
- **Other reads.** The `account_ids` and `hive_permlink_data` joins are by name and text. N+1 only adds rows
  that no vote of N names.

`upsert_votes_partition` reads only `_vote_upsert` and `hive_votes`. Stage A never writes `hive_votes`.
**Votes need no change and no REPEATABLE READ.**

### Payouts of N against posts of N+1

`process_payouts_from_staging` (:1076) resolves versions the same way, in one statement (:1163). Its UPDATE
of `hive_posts` can meet a row that N+1's posts phase updated and committed. READ COMMITTED then rechecks
`hp.id = m.post_id` on the newest row version and recomputes SET from it. The two stages' columns are disjoint:
- **Posts phase:** `updated_at`, `active`, `block_num`, `counter_deleted`, `max_accepted_payout`,
  `percent_hbd`, `allow_*`, `beneficiaries`, `is_muted`, `muted_reasons`, `is_pinned`.
- **Payouts:** `total_payout_value`, `curator_payout_value`, `last_payout_block`, `author_rewards*`,
  `payout`, `pending_payout`, `payout_at`, `last_payout_at`, `cashout_time`, `is_paidout`,
  `total_vote_weight`.
- **Posts-phase reads:** the posts phase reads none of the payout columns (no `cashout`, `is_paidout` or
  `rshares` between :1336 and :2035).

So the result does not depend on commit order. **Payouts need no change.** They can deadlock with the posts
phase on rows both lock (see the write conflicts below).

**REPEATABLE READ would not help and would hurt.** N+1's Stage A may commit before N's Stage B transaction
starts, so a transaction-start snapshot does not exclude it. And an RR payout updating a row that N+1 edited
fails with 40001 (concurrent update). The fix is to make each Stage B reader resolve rows as of its own
block, or as of the end of batch N, as votes and payouts already do.

### The Stage B readers that do see N+1

| reader (Stage B of N) | what N+1's Stage A changes under it | effect | fix |
|---|---|---|---|
| `process_reblogs_from_staging`: the "op before the live version" delete (:879–884) and `validated` (:927) take the version with `counter_deleted = 0` now | a delete, or a delete and re-create, in N+1 | N's reblog of the old version is dropped instead of inserted (today: inserted, then removed by N+1's delete). One fewer `hive_reblogs` id is drawn, so every later reblog id shifts. In the 90-day window N's reblog notification is lost | resolve the version live at the end of N: `block_num_created <= _last_block AND (deleted_block IS NULL OR deleted_block > _last_block)`; the same in `delete_reblog_feed_cache`'s `find_comment_id` |
| posts phase's delete cascade, `del_reblogs` / `del_feed_cache` (:1749–1758, Stage A of N+1) | removes `hive_reblogs` rows N's Stage B has not inserted yet, or that N's reblog notifications still read (:3256) | stale reblog rows survive, and N's reblog notifications are missing | record the batch's deleted post ids in the handoff and run the cascade in N+1's Stage B, before its reblogs (the order today) |
| `flush_reblog_notifications_for_blocks` (:3231) | the cascade above | covered by moving the cascade | — |
| `flush_post_notifications_for_blocks` (:3125) reads `_post_results` | N+1's posts phase refills it (:1356) | N's notifications come from N+1's posts | handoff copy (below) |
| every Stage B function reading `_ops_staging` (votes, payouts, reblogs, account updates, lastread) | N+1's load refills it | wrong batch | handoff copy (below) |
| `process_follows_for_blocks` fills `_follow_notification_events` | `load_ops_staging` (:340, :433) clears it in Stage A | N's follow notifications lost | clear it at the start of the follows phase, in Stage B |
| `_process_post_results_for_cache` → `Posts._merge_post_body` → `PostDataCache.get_post_body` | an edit in N+1 of a post created or edited in N reads the body from `hive_post_data` before N's flush has written it | N+1's patch applies to a stale body | keep cache_merge (1.5 %) in Stage B, after N's flush; `PostDataCache` stays Stage B's alone |
| `process_follows_for_blocks` reads `hivemind_app.operations_view` (hafapp_api.sql:186); notifications and mentions read `blocks_view` | `hive.app_next_iteration` for N+1 recreates the context's views (sync.py:258), and today runs only after the whole batch (sync.py:224) | AccessExclusive waits on the views, or N's reads see the next range | read N's ops from the handoff `_ops_staging`, and block dates from `hafd` tables as `prefetch_ops_staging` does |
| `process_hive_post_mentions` (hive_post_operations.sql:840) | an account created or a post deleted in N+1 | none: it checks `ha.created_at <= op_block.created_at` and `counter_deleted = 0 OR hp.block_num > sn.block_num` | — |
| `process_follows_for_blocks`, `record_batch_mute_changes` and `flush_follow_notifications_for_blocks` look up `hive_accounts` by the names a follow op gives (#520) | N+1's `process_accounts_from_staging` registers the accounts it creates | N keeps a follow, mute, blacklist or follow notification of an account created in N+1 that the sequential sync drops: 5 extra `follows` rows over 1–30 M | resolve each action's names to the accounts that exist at the end of its own block (#521): `created_at <=` the date the action's op carries |

Stage A of N+1 reads nothing Stage B of N writes:
- The posts phase reads `hive_accounts` ids, `hive_permlink_data`, `hive_posts`' own columns and the
  community tables.
- `process_accounts_from_staging` only inserts (`ON CONFLICT (name) DO NOTHING`, :498).
- The community phases write and read community tables, `hive_posts.is_muted`/`is_pinned` and notifications
  with deterministic ids.

## 2. Write conflicts: tables both stages write

| table | Stage A writes | Stage B writes | conflict | handling |
|---|---|---|---|---|
| `hive_posts` | insert; edit, delete, comment_options, mute and pin columns | payout columns; rshares (`MASSIVE_WITH_INDEXES` only, 3.6) | disjoint columns, same rows: row-lock waits, and deadlocks, since the posts phase holds locks from several statements in one transaction while the payout UPDATE locks in its own order | keep 40P01 retry on both sides. The posts phase is one transaction and its id reservation (`_post_id_slots`, :1301) rolls back with it, so a retry is safe. Count deadlocks in the prototype |
| `hive_accounts` | Phase 2 inserts; posts phase `post_count` (:1961, Step 7g) | follows `following`/`followers`; 4b `posting_json_metadata`/`json_metadata`, `lastread_at` | `post_count` and the follow counters lock overlapping rows in different orders: a new cross-stage deadlock source | move Step 7g to Stage B 4b (its delta comes from the handoff `_post_results` plus the deleted ids). Stage A then only inserts, and inserts lock no existing row |
| `hive_reblogs`, `hive_feed_cache` | posts delete cascade | reblogs insert and delete | ordering (section 1) | cascade moves to Stage B |
| `hive_notification_cache` | posts error notifications (type 10), community notifications | post, follow and reblog notifications | none: ids are `notification_id(block date, type, counter)`, `ON CONFLICT DO NOTHING` | — |
| `hive_post_data`, `hive_mentions` | — (once cache_merge is in Stage B) | flush | — | boundary vacuum (Phase 7) no longer runs "with no statement in flight". Stage A does not read `hive_post_data`, so the toast race it avoids (#493) is with Stage B's own flush only, which stays serial |
| staging tables | `_ops_staging`, `_comment_staging`, `_replay_pairs`, `_post_results`, `_post_batch` | `_vote_batch`, `_vote_upsert`, `_reblog_*`, `_follow_notification_events`, `_batch_mute_changes` | `reset_staging_tables` (:275) truncates all of them in one statement and would wait on, or block, the other stage | split the reset per stage, each run between that stage's batches |

Side finding: the follows' "pre-lock in id order" CTEs (`locked AS (SELECT … ORDER BY ha.id FOR UPDATE)`,
six of them, hafapp_api.sql:442–539) are never referenced by their UPDATE. PostgreSQL does not run an
unreferenced non-modifying CTE, so they lock nothing. Planning the first one on the production shape
(`aidev db shape plan`) shows no `locked` CTE and no LockRows node: the plan is just the `delta` CTE and a
primary-key index scan under the ModifyTable. The Phase 4 deadlocks the comment in blocks.py describes
are avoided only by running 4b after Phase 4, not by these CTEs. A pipeline that relies on id-ordered locking
has to reference them, for example `WHERE ha.id IN (SELECT id FROM locked)`.

## 3. Ordering that must hold

- **Votes before payouts within a batch.** Both are in Stage B, and Stage B keeps its order (3.5 before 4).
- **`hive_posts` ids.** They are drawn only in Stage A, through `_post_id_slots`, in batch order, with
  Stage A serial.
- **`hive_votes` ids.** They are drawn only in Stage B (`nextval` at :711, in `ord`), with Stage B serial.
- **Ids that follow them.** `hive_reblogs` ids are drawn in Stage B only, and in today's order once reblogs
  resolve as of the end of N. `hive_permlink_data`, `hive_category_data`, `community_op_counter` and
  `hive_moderation_log` are Stage A only. Notification ids are deterministic.
- **The rule this rests on.** Every sequence keeps a single writer, and it stays in one stage. A change that
  draws a sequence in the other stage breaks the "same ids as today" property.

## 4. Restart and resume

Today the main loop commits the context advance together with a `_batch_queue` row (sync.py:276–281). The
one in-flight batch is replayed from it (`_replay_crashed_batch`, sync.py:381; `LIMIT 1`), and the row is
deleted after the whole batch (sync.py:593). With two batches in flight:
- **`_batch_queue` holds a row per in-flight batch.** The context advances for N+1 once N's Stage A has
  committed, with N+1's row in the same transaction. Each row gets a `stage_a_applied` marker, set in the
  transaction of N's last Stage A phase (3a).
- **The markers are read per batch.** `posts_applied`, `post_data_applied` and `follows_applied`, and
  `_batch_post_results`, are read with `WHERE first_block = …` instead of from the only row (blocks.py:409,
  hafapp_api.sql:148, :367). A row is deleted when its Stage B commits.
- **Resume rule.** Replay the rows in block order, one at a time, without pipelining:
  - for a row with `stage_a_applied`, Stage B only, with its handoff rebuilt from `_batch_post_results`
    (`restore_batch_post_results`) and `load_ops_staging`;
  - for a row without it, the whole batch with today's guards.
- **Why Stage A must not rerun.** Stage A of N must not rerun once N+1's Stage A has committed. Today a replay
  reruns Phase 2 and 3a, which is harmless only because nothing after N has run. With N+1 applied, N's
  setRole, updateProps or mutePost would overwrite N+1's.
- **Stage B guards after N+1's Stage A.**
  - votes: block-resolved, and `num_changes`/`block_num` guard;
  - payouts: block-resolved, and `last_payout_block` guard;
  - reblogs: `ON CONFLICT DO NOTHING` once they resolve as of the end of N;
  - follows: `follows_applied`, and `_batch_mute_changes`, which only Stage B writes and so stays one-batch;
  - account updates and lastread: SET values; N+1's Stage B has not run;
  - flush: `post_data_applied`;
  - notifications: `ON CONFLICT DO NOTHING`, and the mute tables have not moved past N.
- **Context position.** The HAF context is already one batch ahead of the completed data today. Under the
  pipeline it is up to two ahead, and `_batch_queue` stays the record of what is unfinished.
  `_recover_skipped_live_blocks` already returns when `_batch_queue` has rows (sync.py:430).

## 5. Staging double-buffering

Each stage is serial, so a table only one stage uses needs one set. Two tables are written by Stage A and read
by Stage B, and need one set per in-flight batch:
- `_ops_staging`: Stage B's votes, payouts, reblogs, account updates, lastread and the follows rewrite read it;
- `_post_results`: notifications, cache_merge and Step 7g read it.

The deleted-post ids for the cascade join them. Two ways:
- **Stage B reads `_ops_staging_b` and `_post_results_b`.** It is filled at the handoff by `INSERT … SELECT`,
  or the pair's names are swapped while neither stage is in a statement.
  - The copy costs up to one more load of 10,000 blocks of ops per batch (load is 8.1 %).
  - The rename swap costs nothing, but needs both stages at a barrier and relies on plan invalidation.
  - The Stage B functions (`prepare_votes_from_staging`, `process_payouts_from_staging`,
    `process_reblogs_from_staging`, `process_account_updates_from_staging`, `process_lastread_from_staging`,
    the three notification flushes, `restore_batch_post_results`) change their table names: about 10
    functions, plus `process_follows_for_blocks` moving from `operations_view` to the staging table.
- **A slot column on `_ops_staging` and `_post_results`, with every reader filtering on it.** This needs the
  same reloptions (autovacuum off since #495/#478), and the per-load ANALYZE then describes both slots.

The duplicate needs `autovacuum_enabled = false`, as `_ops_staging` has since #495, and its own entry in a
per-stage `reset_staging_tables`. Otherwise it brings back the plan stalls those issues fixed. Python side:
- a `PostDataCache` per batch, or Stage B as its only user;
- `OpsPrefetch` starting N+2's prefetch when N+1's load commits;
- a Stage B thread with its own connections, separate from today's 3 Phase 4 and 4 vote connections;
- the main loop calling `app_next_iteration` after Stage A instead of after the whole batch.

Estimated size: about 15 SQL functions changed, one schema change (`_batch_queue` key and marker, two handoff
tables), and blocks.py/sync.py restructured around two threads. That is several hundred lines, closer to a
feature than a flag.

## What this does not answer, and how to measure it

**Not run here: the prototype, the 5 M correctness run and the 10–30 M timing.**
- **The prototype.** A crude prototype that only overlaps the stages and duplicates the staging tables
  diverges by construction in reblogs, reblog ids, reblog and follow notifications and edit bodies
  (section 1). Comparing it with the current code would measure those known bugs, not pipelining.
- **What a meaningful prototype needs.** It needs the fixes in sections 1 and 2 (reblogs as of the end of the
  batch, the cascade and Step 7g in Stage B, cache_merge in Stage B, the handoff pair, Stage B off the context
  views). That is most of the implementation.
- **The data.** No HAF copy at 30 M or beyond is available to this workflow (the session stack has the 5 M
  fixture only, and steem-20 is production).
- **Status.** The 25 % threshold is therefore not measured. The estimate above is the replay of measured
  per-batch times with an assumed contention factor.

To measure it, on a non-production HAF copy at or past 30 M, set up like `../massive-sync-batch-size/` (ZFS
clones of one installed snapshot, steem-20's `50-perf.conf`):
1. **Base run.** Hivemind at the base commit, `hive sync --test-max-block=30000000` (since #523,
   `--massive-sync-pipelined=false` for a sequential base) from a snapshot taken
   after syncing to 10,000,000. Keep every `[PHASE-SUMMARY]` line with a timestamp (`fidelity_run.sh` does
   this). Once a second, `activity_sampler.py` records host CPU (busy, user, system) and IO wait from
   `/proc/stat`, and `pg_stat_activity` rows counted by application, state and wait event, one JSON line per
   sample (`activity_sampler.py --summary` prints each run's mean CPU and IO wait and its top wait events);
   `sampler.py` records the peak `RssAnon`/`VmRSS` of the postgres and hive processes. `fidelity_run.sh` and
   `run.sh` start both. Count `deadlock detected` lines in PostgreSQL's log.
2. **Pipelined run.** The same with the prototype. Log each stage's start and end per batch, so the measured
   overlap and the slowdown of each stage against its sequential time can be read off and put into
   `simulate.py`.
3. **Compare the results.**
   - `../massive-sync-batch-size/fidelity_dump.sql` plus `fidelity_compare.py` on both runs.
   - Add dumps of `hive_accounts` (counters, metadata, `lastread_at`, `post_count`), `follows`, `muted`,
     `blacklisted`, `follow_muted` and `follow_blacklisted` on natural keys, and of `hive_reblogs` with ids.
   - Then the #477/#482 one-block checks (`fidelity_one_block.sh`) over a window that holds deletes and
     re-creates of reblogged posts.
4. **Kill tests.** Kill the pipelined run with Stage A of N+1 committed and Stage B of N not, and again with
   N's flush committed. Restart and compare with the uninterrupted run.

Proceed to the implementation if the pipelined run is at least 25 % faster over 10–30 M (base about 805
blocks/s here, stalls removed) and every dump is identical.

## Pipelined massive sync: `--massive-sync-pipelined` (#512, default since #523)

The design above is implemented behind a sync option (#512). It was off by default until #500 measured it on
steem-19 over blocks 10–30 M: 27 % faster than sequential, no deadlocks with #517, and every natural-key dump
identical to sequential with #520. Since #523 it is on by default.

### Switching it off

`hive sync --massive-sync-pipelined=false` (or `MASSIVE_SYNC_PIPELINED=false`) runs each batch sequentially, as
before #512. The option applies to the two massive stages only. A crash replay runs its batches one after the
other, and live sync is unchanged: at the first live iteration the handoff tables are dropped
(`set_stage_b_handoff(FALSE)`).

With the option off, a batch runs its phases in the pre-#512 order and on the same connections, with the order-neutral
fixes below. Stage B then reads views of Stage A's tables, so its statements plan as they did on those tables.

### What runs where

- **Stage A:** load, accounts and communities, posts, community post ops. It runs on the massive sync thread and
  its connection (`hivemind_massive_instance`). Its last transaction sets `_batch_queue.stage_a_applied`.
- **Stage B:** votes, rshares (`MASSIVE_WITH_INDEXES`), Phase 4 and 4b, flush, notifications, boundary vacuum. It
  runs on its own thread (`Blocks._stage_b_task`) and connection (`hivemind_stage_b_instance`), with the votes,
  Phase 4, flush and notification connections it already had. When Stage B ends, it deletes its batch's
  `_batch_queue` row.
- **The order of a batch.** Stage A of batch N ends, then waits for Stage B of N−1. The handoff
  (`hand_off_to_stage_b`) runs while neither stage is in a statement, and Stage B of N starts. The main loop then
  calls `hive.app_next_iteration` for N+1, which therefore follows Stage A of N, not the whole batch. Stage A of N+1
  runs beside Stage B of N. This is the two-handoff-set flow shop that `simulate.py` replays.

### The fixes, as implemented

- **Reblogs.** `process_reblogs_from_staging(_last_block)` resolves the post version live at the end of the batch
  (`block_num_created <= _last_block AND (counter_deleted = 0 OR block_num > _last_block)`). It does so in the
  "op before the live version" delete, in `validated`, and in `delete_reblog_feed_cache(…, _last_block)`.
- **Post-delete cascade.** The posts phase records every version it deletes in `_deleted_posts`, both the
  set-based deletes and the replayed ones; `delete_hive_post` no longer cascades. The first statements of
  `process_reblogs_from_staging` remove the reblogs and feed cache rows of those versions, before the batch's
  reblogs.
- **`post_count`.** Step 7g is `process_post_counts_from_staging(_first_block)`, run in 4b. It reads the handoff's
  `_post_results_b` and `_deleted_posts_b`, and applies once per batch (`_batch_queue.post_counts_applied`), since
  it adds deltas.
- **Body merge.** cache_merge stays in Stage B (Phase 3b, beside Phase 4). Only Stage B uses `PostDataCache`.
- **Follow notifications.** `process_follows_for_blocks` clears `_follow_notification_events` before it collects
  them; the loads no longer clear it.
- **Context views.** `process_follows_for_blocks` reads the batch's follow ops from `_ops_staging_b`
  (`op_type_id = 18 AND val->>'id' = 'follow'`). On the 5 M fixture that selects exactly the ops HAF types as
  `follow` custom_json: all 477,697 follow-typed ops carry `id` `follow`, and every reblog-typed op carries
  `reblog`. The post and follow notification flushes and `process_hive_post_mentions` take block dates from
  `hafd.blocks`.
- **Batch queue.** `_batch_queue` holds a row per in-flight batch. Every marker is read and set by the batch's
  `first_block`. `_batch_post_results` and `_batch_deleted_posts` keep the posts phase's results and deletes per
  batch, keyed by `first_block`.
- **Sequences.** `hive_posts` ids are still drawn in the posts phase (Stage A). `hive_votes` and `hive_reblogs` ids
  are still drawn in Stage B, and the reblogs draw them in today's order, since they resolve as of the end of the
  batch.
- **Deadlocks.** The accounts and communities, posts and community post ops transactions retry on 40P01, as do
  Stage B's rshares update and 4b; Phase 4, the votes partitions and the notification flushes already did. Each
  retry is counted per stage.
- **`hive_posts` lock order (#517).** The retries above were hit: 16 posts-phase/payouts deadlocks over 10–30 M. Each
  stage's transaction that updates existing `hive_posts` rows now locks them in ascending `id` order before it
  updates any:
  - the posts phase, in one `SELECT … ORDER BY hp.id FOR UPDATE` at its start (Step 0), over the live version of
    every post a comment, delete or comment_options op of the batch names. Its later statements, each in its own
    order, then touch only rows it holds or inserts;
  - the community post ops (`process_community_from_staging(…, 2)`), over every version of each post a mute or pin
    op names, before the per-op updates;
  - the payouts and `update_posts_rshares`, in a `FOR NO KEY UPDATE` CTE ordered by id that the UPDATE reads its
    rows from (an unreferenced CTE locks nothing, #501).

  `hive_accounts` needs no ordering across the stages: Stage A only inserts accounts. The 40P01 retries stay as a
  safety net. `.aidev/stage_lock_order_check.py` checks the order and a posts phase beside payouts and rshares on
  the same posts.
- **Accounts as of the action's block (#520, #521).** `process_follows_for_blocks` (the reset actions' follower,
  the bulk resolution of follower and following, before the batch's dedup keeps the last action per pair),
  `record_batch_mute_changes` and `flush_follow_notifications_for_blocks` see only accounts with `created_at <=` the
  date the action's op carries (`_ops_staging.block_date`, the date of the block before it; the notification flush
  reads it from `hafd.blocks`). An account created in the action's own block exists for it; one created later,
  even in the same batch, does not, as in live sync, so the result no longer depends on where batches start
  (#520 bounded by the batch's last block, which kept a follow of an account created later in the same batch).
  The other Stage B readers cannot name an account the next batch creates: a vote's voter, a reblog's account, an
  account update's account and a `setLastRead`'s account sign the op; a vote's author and a reblogged post's author own a post that exists by the batch's end (reblogs bound the post by `_last_block`); the
  payouts, post counts, `update_posts_rshares` and the post and reblog notification flushes go by post or account
  id; and mentions already bound each account by its block. `.aidev/pipelined_follow_accounts_check.sql` runs the
  same blocks in three batch layouts, sequential and pipelined.
- **The shared connection.** In pipelined mode Stage B's boundary vacuum reads its thresholds on Stage B's
  connection, because the shared connection is the main loop's, busy with the next iteration. Payouts take the
  cashout bound `set_end_of_sync_lib` set for their own batch, not the one the next batch's start set.

### The handoff: `_b` tables, not a slot column

Stage B reads `_ops_staging_b`, `_post_results_b` and `_deleted_posts_b`.
- **Why not a slot column.** A slot column would put a predicate into every Stage A and Stage B reader, about 20
  functions, and the per-load `ANALYZE` would describe two batches at once.
- **What the `_b` names cost.** They change only Stage B's readers, and Stage A's statements stay as they are.
- **Default mode.** The three objects are views of Stage A's tables (`set_stage_b_handoff(FALSE)`).
- **Pipelined mode.** They are tables out of autovacuum, and `reset_stage_b_staging_tables` truncates them with
  Stage B's other tables. `reset_stage_a_staging_tables` covers Stage A's, so each stage truncates its own tables
  between two of its batches.
- **How the handoff fills them.** `_ops_staging` trades names with `_ops_staging_b`, indexes included. A copy would
  cost Stage A, on the critical path, another load of the batch's operations, and with the swap Stage B reads the
  statistics the load analyzed. The posts phase's results and deletes are small, so they are copied, without the op
  bodies, which only Python's body merge reads.

### Restart and resume

`_replay_crashed_batch` replays the rows in block order, one at a time:
- **A row with `stage_a_applied`** runs Stage B only (`Blocks.process_stage_b_of_batch`). Its operations are
  reloaded from HAF's tables (`prefetch_ops_staging`), as the context's views may already show the next range, and
  its posts phase's results and deletes come from `restore_batch_post_results(first_block)`.
- **Any other row** runs the whole batch, with the guards as before.

### What #500 reads

With the option on, every batch logs two `[STAGE-TIMING]` lines next to its `[PHASE-SUMMARY]` (none with it off):

```
[STAGE-TIMING] blocks=F-L stage=A start=<epoch s> end=<epoch s> elapsed=<s> deadlocks=<n> wait_for_b=<s> handoff=<s> <A's phases>
[STAGE-TIMING] blocks=F-L stage=B start=<epoch s> end=<epoch s> elapsed=<s> deadlocks=<n> <B's phases> <Phase 4's lanes>
```

- **Overlap.** Stage A of N+1 overlaps Stage B of N from `max(start)` to `min(end)` of the two lines.
- **Waiting.** `wait_for_b` is how long Stage A of N waited for Stage B of N−1 before its handoff.
- **Slowdown.** Each stage's `elapsed`, set against the base run's sum of that stage's `[PHASE-SUMMARY]` phases,
  gives the slowdown factor for `simulate.py`.
- **`[PHASE-SUMMARY]`** is written when the batch's Stage B ends. It holds both stages' phases and `handoff`.
- **Deadlocks.** `deadlocks` counts the 40P01 retries per stage. PostgreSQL's log has the matching `deadlock
  detected` lines.

### Kill tests

`--test-pipeline-kill=POINT:F` exits the process at once, as a crash would, in the batch starting at block F:
- **`stage_a_committed`** holds Stage B of F before its first statement, and exits when the next batch's Stage A
  has committed (pipelined only).
- **`payouts_committed`** exits in Stage B's votes lane right after the batch's payout partitions have committed
  (#526). Its reblogs and follows lanes may or may not have committed by then, and 4b has not run.
- **`flush_committed`** exits right after the batch's post data flush has committed.

`../massive-sync-batch-size/fidelity_run.sh` runs one with `PIPELINE_KILL=POINT:F`, restarts, and dumps. The
runs below passed `SYNC_ARGS=--massive-sync-pipelined=true`, from before #523 made it the default; a sequential
arm now passes `SYNC_ARGS=--massive-sync-pipelined=false`. `fidelity_dump.sql` now also dumps `hive_accounts`
(every column), the follow, mute and blacklist lists on natural keys, `hive_reblogs` with their ids, and the feed
cache. `fidelity_compare.py` diffs them too.

### Results on the 5 M fixture

Setup: HAF 5 M fixture on steem-4 in `/scratch/hm512`, set up like `../massive-sync-batch-size/fidelity.md`. Every run
is a ZFS clone of one install made at the base commit (5d1b7a5a8), with reptracker synced to 4,990,000, and syncs
in 10,000-block batches to 4,990,000. Each run is compared with the base commit's run by `fidelity_compare.py`,
over posts, votes, notifications and their ids, mentions, post data, post ids, accounts, the five follow and mute
lists, reblogs with ids and the feed cache.

| run | result |
|---|---|
| option off | 15 of 15 dumps identical |
| option on | 15 of 15 identical |
| on, killed at `stage_a_committed:4500001`, restarted | 15 of 15 identical. At the kill, `_batch_queue` held 4,500,001 (`stage_a_applied`, no flush) and 4,510,001 (`stage_a_applied`) |
| on, killed at `flush_committed:4730001`, restarted | 15 of 15 identical. At the kill, 4,730,001 had `post_data_applied`, and 4,740,001 its Stage A |
| on, killed by `docker kill` once the context reached 4,500,000, then one block at a time to 4,510,000 (`fidelity_one_block.sh`), against base's 10,000-block run | 15 of 15 identical. At the kill, `_batch_queue` held 4,480,001 and 4,490,001 |

**No crafted test needed for most cases; one is.** The fixture holds 12 reblog ops (blocks 4.59–4.97 M), and none
of the reblogged posts is deleted later. `tests/sql/pipelined_stage_order.sql` therefore checks the case of a
reblogged post the next batch deletes and re-creates. It runs two batches in the sequential order, in the
pipelined order and one block at a time, and expects the same posts, reblogs, `hive_reblogs` ids drawn, reblog
notifications and `post_count`.

**Two bugs the first runs found.**
- **Stage A's reset.** It ran after Stage A's own load, and with 10,000-block batches it is due every batch, so
  it truncated each batch before its handoff. Stage B saw no votes or follows. The reset now runs before the
  load.
- **Phase 4's retry.** It reran all three tasks, so a reblogs task that had committed would draw `hive_reblogs`
  ids again. The fixture's reblogs did not show it. Now only the rolled-back tasks run again.

**Indicative timing, not #500's measurement.** These runs shared the host with up to five other syncs. The option
on took 477.6 s from the first Stage A to the last Stage B, against 583.4 s for base's first-to-last batch, which
ran beside two other syncs. Summed per batch:
- Stage A elapsed 256.6 s, Stage B elapsed 452.2 s, overlapping for 234.8 s;
- Stage A waited 216.0 s for Stage B, since Stage B dominates at 5 M, where votes are most of a batch.

Deadlocks were all resolved on their first retry: 13 in the posts phase (Stage A against the payouts) and 10 in
Phase 4.

**With the `hive_posts` lock order (#517).** Same fixture, setup and batches, the tree at #517, run as `on517`
(option on) and `off517` (option off), at the same time on steem-4 on 2026-11-24:
- `on517` retried no deadlock: no `deadlock detected` in its log, and all 998 `[STAGE-TIMING]` lines have
  `deadlocks=0` (the run above: 23 retries);
- `on517` and `off517` are each identical to base's `b10k` run in all 15 dumps;
- indicative timing, the two runs sharing the host: `on517` took 428.3 s from the first Stage A to the last Stage B
  (Stage A 245.9 s, Stage B 384.7 s, overlapping for 205.6 s). Summed `[PHASE-SUMMARY]` totals of the option-off
  runs: `off517` 628.9 s (posts 189.4 s), `b10k` 600.7 s (posts 175.4 s), `off10k` 643.0 s (posts 178.1 s).

## Shorter stages: Phase 4 lanes, payout partitions, a renamed load (#526)

On the steem-20 rebuild `20261125-bd170b60` Stage B bounded each batch: votes (`prepare_votes_from_staging` 1.6 s,
then the four upsert partitions 0.7 s), then Phase 4 with `process_payouts_from_staging` (3.1 s) as its long pole
beside reblogs (0.5 s) and follows (1.4 s). Stage A spent 0.8 s of its 6 s copying the prefetched operations
(`load_ops_staging_from_prefetch`). Three changes shorten the two critical paths.

### Stage B: three lanes, payouts in partitions

Phase 4 (`Blocks._run_stage_b`) runs three lanes at once, each on connections of its own, with the body merge
(Phase 3b) on Stage B's thread beside them:
- **votes, then payouts** (`_run_votes_and_payouts`): the votes phase as before, then in `MASSIVE_WITH_INDEXES`
  the rshares update of the voted posts, then the payouts. The rshares update reads the votes and, like the
  payouts, updates the voted posts, so the lane keeps the three in that order;
- **reblogs**;
- **follows**.

The votes no longer wait in front of the reblogs and follows. Neither reads or writes anything the votes write,
and with the foreign keys dropped through massive sync the votes take no lock on the `hive_accounts` rows the
follows lock (an FK check's `FOR KEY SHARE` would conflict with their `FOR UPDATE`). 4b stays after all three
lanes, serialising the `hive_accounts` writers as before.

The payouts run in `--massive-payout-workers` partitions (default 4, `MASSIVE_PAYOUT_WORKERS`), each on a
connection of its own (`Payouts`, like `Votes`' upsert workers). `process_payouts_from_staging(_last_safe_cashout_block,
_part, _parts)` applies the payout ops whose `author/permlink` hashes to `_part`. All versions of a post share
its author and permlink, so the partitions update disjoint `hive_posts` rows, and each partition locks its rows in
id order as #517 requires. A deadlock retry runs every partition again (`_run_parallel_sql`), and so does a
crash replay of Stage B. That is safe: a partition run again after committing changes nothing, as the
`last_payout_block` guard keeps `author_rewards` and every other column is set, not added to.
`.aidev/stage_lock_order_check.py` checks that the partitions together update each post once, and that they
finish beside the posts phase on the same posts without a deadlock.

Stage B's critical path becomes the longest lane rather than the votes plus the longest Phase 4 task: on that
rebuild's means, from about 2.3 + 3.1 = 5.4 s to about 2.3 + 3.1 / 4 = 3.1 s, assuming the partitions scale.
Each one still scans every payout op of the batch to hash it, but it aggregates and updates only its own
share. That is an estimate, not a measurement (see below).

### Stage A: the prefetched operations are renamed, not copied

`prefetch_ops_staging` already loads the next batch's operations on a thread and connection of its own while
Stage A runs. It now also sorts them by id, indexes them and analyzes them (`_ops_staging_next` has the indexes of
`_ops_staging`). With the handoff tables, `take_prefetched_ops_staging` then takes the rows by trading the names
of `_ops_staging_next` and `_ops_staging`, indexes included, as the handoff trades `_ops_staging` with
`_ops_staging_b`. The next prefetch truncates what `_ops_staging` held. That removes the copy and the `ANALYZE`
(about 0.8 s per 10,000 blocks on that rebuild) from Stage A. The batch's rows, their physical order and their
statistics are those the copy left. A prefetch covering more than the batch has the extra blocks deleted (and
the table analyzed again), as at a stage change.

The two other modes still copy (`load_ops_staging_from_prefetch`). With the option off, `_ops_staging_b` is a view
of `_ops_staging`, and a view follows its table by OID, so a rename would leave it reading `_ops_staging_next`. A
crash replay's Stage B reload copies too. `.aidev/ops_prefetch_check.sql` checks that the rename stages the rows
and order the load does, for a shorter range too, keeps both tables' indexes, and is refused without the handoff
tables.

The prefetch does not move to batch N+2. Prefetching N+1 runs beside all of Stage A of N (posts alone take about
4 s, the prefetch about 1.2 s), so only its copy was on the critical path. With no new stage there is no new
staged batch for a crash to leave behind: the prefetched table is unlogged and marker-free, as before, and a
restart reloads every batch from HAF.

### Sub-phase times

`[STAGE-TIMING]` lines now name their phases (format above):
- **The A line** gives Stage A's phases: `staging_reset_a`, `load`, `accounts_community`, `posts`, `community_post`.
- **The B line** gives Stage B's sequential phases (`parallel`, `flush`, `notify`, `vacuum`, `staging_reset`), then
  Phase 4's lanes and sub-phases: `votes_prepare`, `votes_upsert`, `rshares_incr` (`MASSIVE_WITH_INDEXES`),
  `payouts`, `votes_payouts` (the whole lane), `reblogs`, `follows`, `cache_merge` (when it ran) and
  `account_updates` (4b).

The lanes overlap one another and all fall within `parallel`. `[PHASE-SUMMARY]` therefore keeps only phases
that do not overlap, so its `total` is their sum: `votes` and `rshares_incr` are now part of `parallel`, and
`cache_merge`, which `total` used to count twice, is on the B line only.

### Not measured here

The acceptance runs were not done in this change's workflow:
- the #500 harness on steem-19 over 10–30 M (sequential base and pipelined, at the forked tip);
- the #524 fidelity dumps;
- the kill-and-resume runs at `payouts_committed`;
- the steem-20 rebuild comparison.

The expected gain per change above is derived from the rebuild's per-statement means, not measured. The partitioned
payouts' scaling, in particular, depends on the CPU and IO they get beside Stage A.

