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
1. **Base run.** Hivemind at the base commit, `hive sync --test-max-block=30000000` from a snapshot taken
   after syncing to 10,000,000. Keep every `[PHASE-SUMMARY]` line with a timestamp (`fidelity_run.sh` does
   this). Sample CPU, IO wait and `pg_stat_activity` wait events once a second (`sampler.py`). Count
   `deadlock detected` lines in PostgreSQL's log.
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
