# hivemind!838's write-path ideas, measured one at a time

Measured on 2026-11-04 on steem-20's full mainnet database (`haf-haf-1`, `haf_block_log`,
HAF `b3c8655d`, PostgreSQL 18.6, 32 cores, 121 GiB). The live hivemind is
`a751721d`, live-syncing at head (block 111,360,902 at the start). Statement-level runs
used the SQL of this tree (`87ef0c2e`, which contains #425) on a throwaway ZFS clone of
the same database. Plan checks used the pinned mainnet shape `9381e39f59cb`.

## Answer

| idea | recommendation | why, in one line |
|---|---|---|
| 1. drop `reset_autovac`'s per-table overrides | **keep the overrides** | in live sync they cost ~0.6 s of one autovacuum worker per vacuum, 2–3 times an hour, plus a ~4 s analyze every hour or two; without them `hive_posts` would not be analyzed for 2.5–4 months or vacuumed for about a year |
| 2. `work_mem = RAM/32` for finalization | **drop it** | no query run through `_execute_query_with_modified_work_mem` spills at /64; /32 changes no time; the one big query sets its own `work_mem = '4GB'` |
| 3. split `hive_posts` into static and mutable tables | **no-go** | it would remove ~1.4% of live-sync WAL and ≤ ~1% of block time, for 1–9% more buffers on most hot reads (+28% on account posts, 2× on `get_profile` as a plain view), and it means rewriting the largest table and every reader |

None of the three ideas should land, so this analysis files no implementation
follow-up. #280 ("Review overrides of autovacuuming of hivemind tables") is answered by
section 1 and can be closed with a reference to #434.

## Setup

- Settings that matter here: `autovacuum_naptime 60s`,
  `autovacuum_vacuum_cost_limit 5000`, `autovacuum_vacuum_cost_delay 2ms`,
  `autovacuum_max_workers 5`, `default_statistics_target 500`, `work_mem 64MB`,
  `hash_mem_multiplier 2`, `shared_buffers 16GB`, `wal_level minimal`,
  `full_page_writes off`, `fsync off`, `log_autovacuum_min_duration 0`.
- Two live-sync windows of 61 minutes each, back to back. **A** had the overrides as
  `reset_autovac` sets them. **B** reset the three tables to the server defaults
  (`ALTER TABLE … RESET (autovacuum_*)`). The overrides were put back right after B
  and checked in `pg_class.reloptions`.
- Data sources:
  - `pg_stat_user_tables` and relation sizes, sampled every 60 s;
  - `pg_waldump --follow` over both windows, attributed to tables and indexes by
    relfilenode;
  - `pg_stat_statements` deltas (WAL bytes per statement);
  - the PostgreSQL autovacuum log;
  - hivemind's `[PROCESS LIVE SQL] blocks N-N in Xs` lines for the time of each block.
- The live write path that votes and payouts take (`update_posts_rshares`,
  `process_payouts_from_staging`, the `hive_votes` upsert) is identical in `a751721d` and
  `87ef0c2e`. Only `process_posts_from_staging`, which creates posts, differs.
- The clone: an atomic `zfs snapshot -r` of the HAF datadir at 08:09 UTC (block
  111,363,453), started as a second PostgreSQL 18.6 on a Unix socket only, with
  `shared_buffers 8GB` and autovacuum off. It was destroyed afterwards, together with
  the snapshot. Production was not written to, apart from the reloptions toggle in
  window B.

## 1. Autovacuum overrides (`reset_autovac`)

### Live-sync windows

| | A: overrides | B: defaults |
|---|---|---|
| time, blocks | 06:01–07:02, 111,360,902–111,362,121 (1,219) | 07:04–08:05, 111,362,161–111,363,379 (1,218) |
| votes (`hive_votes` rows written) | 9,867 | 4,399 |
| **hive_posts** inserts / updates | 332 / 7,462 | 287 / 4,687 |
| HOT updates | 3,397 (**45.5%**) | 1,886 (**40.2%**) |
| `n_dead_tup` start → end | 2,452 → 637 | 755 → 3,806 (rising steadily) |
| autovacuum / autoanalyze runs | **3 / 1** | **0 / 0** |
| heap size growth | 0 | 0 |
| index size growth (34 GB of indexes) | +576 KiB | +408 KiB |
| **hive_post_tags** inserts / updates / dead | 396 / 0 / 6 | 344 / 0 / 6 |
| autovacuum / autoanalyze runs | 0 / 0 | 0 / 0 |
| **hive_accounts** updates (HOT) / dead | 165 (81.8%) / 483 → 554 | 122 (82.8%) / 557 → 579 |
| autovacuum / autoanalyze runs | 0 / 0 | 0 / 0 |
| block time mean / median / p90 / p99 / max | 39.8 / 30.3 / 70.7 / 82.5 / 175.9 ms | 36.5 / 27.6 / 67.6 / 80.0 / 171.4 ms |
| WAL (`pg_stat_wal`) | 199.7 MB | 156.6 MB |

Window B carried 55% fewer votes and 37% fewer `hive_posts` updates than A (traffic
varies hour to hour), so B's 8% shorter blocks reflect lighter traffic, not the
autovacuum setting. Neither window shows any block-time effect that autovacuum could
cause: in A each vacuum ran on its own worker for about half a second.

What a `hive_posts` autovacuum under the overrides does (log, all four runs in the
morning and the one after window B):

- It runs for 0.53–0.61 s, scans 3.7% of the 5.66M heap pages (the pages that are not
  all-visible) and removes 518–1,142 tuples.
- It writes 13–29 KB of WAL.
- `index scan bypassed`: the pages holding dead item identifiers are 0.68–0.69% of the
  heap, under PostgreSQL's 2% bypass threshold. So no run vacuums the 19 indexes.
- An autoanalyze of `hive_posts` takes 3.5–4.0 s and reads 149k pages.
- The hour without vacuum cost nothing to catch up. The first autovacuum after the
  overrides came back (08:07:11, 25 s later) removed 1,142 tuples in 0.54 s, the same as
  a routine run. On-access pruning had already reclaimed most of the space: the heap did
  not grow in either window.

Two side observations:

- ANALYZE resets `n_dead_tup` to its sample estimate (629,582 at 06:17), which triggers
  an extra vacuum a minute later.
- `hive_post_tags` and `hive_accounts` never reached their override thresholds in either
  window (no updates, and ~20 dead tuples an hour, respectively). For them the overrides
  change nothing in live sync.

### Without the overrides, projected from window B

`hive_posts` reltuples are 136.4M, so the defaults trigger:

- a vacuum at 27.3M dead tuples (0.2 × reltuples). At B's rate of 3,051 per hour that is
  about **a year**;
- an analyze at 13.6M changed rows (0.1 × reltuples). At 5k–7.8k per hour that is
  **73–114 days**.

### Do planner estimates go stale?

Range predicates on a column that leads an index (`id`, `block_num`, `block_num_created`,
`payout_at`) stay accurate on stale statistics: the planner reads the real minimum and
maximum from the index when a value falls past the histogram. Columns that lead no
index are a different matter. The pinned shape's statistics are 8 days old (captured
2026-10-27), which models 8 days without analyze. Planned estimates for posts created
after a timestamp:

| predicate | true rows (steem-20) | fresh statistics (steem-20) | 8-day-old statistics (shape) |
|---|---|---|---|
| `created_at > 2026-11-03 06:00` | 9,155 | 9,683 | 2,741 |
| `created_at > 2026-10-28 06:00` | 63,769 | 68,922 | 2,741 |
| `block_num_created > 111,332,000` (indexed) | 9,155 | 10,088 | (the shape's indexes are empty, so it cannot show the endpoint lookup) |

Past the histogram's last bound the estimate is the same for any window size: 23 times
too low for a week. No hot API statement filters `hive_posts` on a range of a column
that leads no index (they use `payout_at`, `id`, `block_num`), so the practical risk is
limited today. It is still a risk that the overrides remove for the price measured
above.

### Recommendation

Keep `reset_autovac` as it is. Massive sync was not re-run: a replay of 111M blocks
takes days. The 60–70M-block A/B recorded in `DbState.MASSIVE_VACUUM_THRESHOLDS`' comment
already found the hot tables' concurrent autovacuums free in wall time, and nothing
measured here points the other way. The 1.5 h that !838 reported came with unrelated
`bgwriter` changes, and nothing here attributes it to the overrides.

## 2. Doubled finalization `work_mem` (`divide_factor` 64 → 32)

`get_memory_amount()` reads 124,087.77 MB in the hivemind container (the host's RAM), so
/64 = **1938MB** and /32 = **3877MB**. Every statement that finalization runs through
`_execute_query_with_modified_work_mem` was run on the clone with `EXPLAIN (ANALYZE,
BUFFERS, SETTINGS)` at both values, alternating, two rounds, with `log_temp_files = 0`.
UPDATE, INSERT and DELETE were run as the SELECT that feeds them: `work_mem` governs only
the sorts, hashes and aggregates of that read. Times are from round 2 (warm):

| call | runs in | plan's memory nodes | spills at /64 | /64 | /32 |
|---|---|---|---|---|---|
| `recalculate_all_posts_votes_and_children()` | initial | — | — | sets `work_mem = '4GB'` itself, so neither factor reaches it | |
| `update_feed_cache(0, head)`, posts part | initial (Part 0) | none (index scan of 25.2M rows) | no | 177.3 s | 177.0 s |
| `update_feed_cache(0, head)`, reblogs part | initial (Part 0) | none (seq scan of 17.0M rows) | no | 1.17 s | 1.17 s |
| `update_hive_posts_root_id(NULL, NULL)` | initial | none (index-only scan on `root_id = 0`) | no | 0.21 ms | 0.21 ms |
| `clear_muted_notifications()` | initial (Part 1) | parallel hash, 28.9 MB, 1 batch | no | 106 ms | 109 ms |
| reputation notification scores UPDATE | initial | parallel hash, 39.9 MB, 1 batch; memoize < 0.5 MB | no | 1.23 s | 1.23 s |
| `update_hive_posts_children_count(a, b)`, 28,800 blocks | catch-up | hash aggregate 425 kB, quicksort 741 kB, CTE 1.2 MB | no | 56.5 ms | 55.5 ms |
| `update_feed_cache(a, b)`, 28,800 blocks | catch-up | none | no | 2.1 ms | 2.0 ms |

There were no temp files, no `Batches` > 1 and no external sorts in either round. The
first, cold round of the 25M-row feed-cache scan took 193.7 s. That gap is the cache
warming, not `work_mem`.

The largest node needs 40 MB, less than 1/48 of what /64 already grants. Under
finalization's real concurrency, Part 0's feed cache runs next to the `hive_posts`
recompute (fixed 4 GB), and Part 1's `clear_muted_notifications` next to the vote
notifications (session `work_mem`). The doubling would therefore raise only the ceiling,
never the use. /32 is not recommended, so the peak-memory proof the issue asks for in
that case is not needed.

## 3. Splitting `hive_posts` into static and mutable tables

### Write amplification today (window A, `pg_waldump`)

- WAL: 201.9 MB in the hour, 165.6 KB per block. hivemind's tables wrote 21.0 MB of it
  (10.4%) and HAF the rest. `hive_posts` wrote 7.52 MB (3.7%, 6.2 KB per block), 73% of
  it into its 19 indexes and 2.03 MB into the heap.
- Row writes: 4,056 non-HOT updates (`Heap:UPDATE`, 256 B per record), 3,399 HOT
  updates (124 B) and 333 inserts.
- Index entries: every non-HOT row version goes into all 19 indexes. The partial ones
  skip paid-out posts and comments, which gives 74,116 index-tuple inserts, 16.9 per
  row version. That is **7.5 index-tuple inserts and 762 B of `hive_posts` WAL per
  vote** (9,867 votes).
- Static columns: 42,261 of those inserts (57%, 3.15 MB of WAL) went into the 11
  indexes whose columns never change (`ux1`, `author_id_*` ×3, `block_num_created`,
  `community_id_id`, `community_id_*pinned` ×2, `depth`, `parent_id_id`,
  `root_id_id`). Leaving out the 333 new posts, which a split still inserts into
  them, a split would save **~2.9 MB per hour, 1.4% of the WAL**.
- Time (`pg_stat_statements`, 06:12–07:04, 1,035 blocks): the vote UPDATE wrote 2,546
  rows in 339 ms, with 2.00 MB of WAL (784 B per row). The payout UPDATE wrote 2,826 rows
  in 447 ms, with 3.35 MB. Together the statements that update `hive_posts` take
  **0.76 ms of a 39.8 ms block** (1.9%), which bounds what any change to their write
  path can save.

### Prototype on the clone

- Tables: `hive_posts` was renamed to `hive_posts_s`, which keeps its indexes on static
  columns. `hive_posts_m` holds `id` plus the 24 vote-, payout- and child-driven columns
  (`children`, `payout`, `pending_payout`, `payout_at`, `is_paidout`, `sc_trend`,
  `sc_hot`, `*_rshares`, `total_votes`, `net_votes`, `active`, `updated_at`,
  `block_num`, …). It has 6 indexes: primary key, `block_num`, `payout_at`, and `sc_trend`,
  `sc_hot` and `payout + pending_payout`, each partial on `NOT is_paidout`.
- View: a view named `hivemind_app.hive_posts` joins the two halves, and the 6 views
  built on `hive_posts` were re-pointed at it. Every API function therefore reads the
  split unchanged.
- Size and build time: `hive_posts_m` is 29 GB of heap and 7.2 GB of indexes, built in
  1 min 46 s plus 57 s.

**Writes.** Window A's real per-block voted-post sets were replayed (1,045 statements,
3,129 row updates) against both layouts:

| | today (`hive_posts`) | split (`hive_posts_m`) |
|---|---|---|
| WAL | 4.39 MB | 1.95 MB (−56%) |
| index-tuple inserts | 52,068 | 17,314 (−67%) |
| statement time | 0.58 s | 0.30 s (−0.27 ms per block) |

The replay always moves `sc_trend`/`sc_hot` on unpaid root posts, so its HOT ratio
(7.4%) is lower than production's 45%. It overstates the absolute savings and is a fair
comparison of the two layouts.

**Reads.** The 11 hot API calls of `.aidev/project.yaml` `performance.queries`, with
their declared arguments on real data: median of 7 warm runs, and buffers per call.

| call | today | split, inner-join view | split, LEFT JOIN view, `hive_posts_m` vacuumed |
|---|---|---|---|
| bridge.get_discussion | 985 ms, 195k buf | 1,017 ms, 215k (+10%) | 992 ms, 200k (+2%) |
| bridge.get_post | 14.3 ms, 5.3k | 16.7 ms, 5.8k (+10%) | 13.4 ms, 5.7k (+8%) |
| bridge.get_profile | 80.7 ms, 284k | **2,675 ms, 20.7M (×73)** | **168 ms, 570k (×2.0)** |
| condenser.get_follow_count | 1.5 ms, 990 | 2.2 ms, 990 | 2.1 ms, 990 |
| condenser.get_content | 14.3 ms, 4.8k | 16.5 ms, 5.3k (+12%) | 13.8 ms, 5.2k (+9%) |
| bridge.get_account_posts posts | 3.1 ms, 1.6k | 3.7 ms, 2.1k (+31%) | 3.6 ms, 2.0k (+28%) |
| bridge.get_account_posts blog | 145 ms, 182k | 164 ms, 183k (+1%) | 148 ms, 182k (0%) |
| bridge.get_community | 2.5 ms, 1.5k | 3.1 ms, 1.5k | 2.9 ms, 1.5k |
| condenser.get_followers | 30.2 ms, 90k | 31.7 ms, 90k | 26.1 ms, 90k |
| condenser.get_following | 17.6 ms, 26k | 20.7 ms, 26k | 15.2 ms, 26k |
| bridge.get_ranked_posts trending | 127 ms, 137k | 144 ms, 144k (+5%) | 129 ms, 143k (+4%) |
| bridge.get_ranked_posts created/tag | 68.0 ms, 37.7k | 81.7 ms, 39.1k (+4%) | 66.3 ms, 38.3k (+1%) |
| condenser.get_content (replies) | 447 ms, 97.5k | 465 ms, 108k (+11%) | 450 ms, 100k (+3%) |

How to read this table:

- **Timing noise:** the follow calls never touch `hive_posts` (identical buffers), yet
  their times move by −14% to +44%. That is the clone's timing noise for calls of a few
  milliseconds, so the buffer column is the reliable one.
- **Inner join:** PostgreSQL never removes an inner join. Through an inner-join view,
  every row read from the static half probes the mutable half, even when the query
  needs no mutable column. `get_profile` counts `ai-summaries`' 2.0M posts twice, and
  each count became 2.0M primary-key probes.
- **LEFT JOIN:** removable on the unique key when no mutable column is read, so it fixes
  the counts. `get_profile` stays 2× slower for a different reason. Its
  `max(created_at)`, an index LIMIT 1 on today's table, cannot use the min/max shortcut
  behind a join view, so it walks all 2.0M index entries.
- **What a real split would have to do:**
  - query the static table directly wherever no mutable column is needed;
  - copy `depth`, `counter_deleted`, `community_id` and `category_id` into the mutable
    table. The partial indexes behind trending, hot, the payout sorts and the
    community's unpaid posts combine `is_paidout` with those columns. The prototype's
    mutable-side partial indexes carry `NOT is_paidout` only, and the hot ranked calls
    still kept within +4%.

### Go / no-go: **no-go**

Measured upper bounds of the gain:

- ~1.4% of live-sync WAL;
- ~0.3–0.4 ms of a ~40 ms block (the clone replay halves an update cost that is 0.76 ms
  per block in production);
- no measurable bloat. `hive_posts`' heap did not grow in either window, and its indexes
  grew by ~0.5 MiB per hour.

Costs:

- 1–9% more buffers on the hot reads that need both halves, +28% on account posts;
- a 2× regression wherever a view hides a min/max or count shortcut, unless every
  reader is rewritten for the split;
- duplicated columns for the partial indexes;
- a rewrite of the largest table (43 GB of heap, 34 GB of indexes, plus a new 29 + 7 GB
  table), of massive sync, of every view and SQL function, and of HAF's index
  registration.

Live sync is not write-bound: blocks take ~40 ms of a 3 s interval. So the write
savings buy nothing a user would see, and the read cost lands on every API call.

## Not analysed

- **Massive sync (replay) runtime** under ideas 1 and 2. A replay of 111M blocks takes
  days. Idea 2 is settled at statement level: nothing spills, and the one large
  statement ignores the factor. Idea 1 rests on the earlier 60–70M A/B cited above.
- **The recompute at its own 4 GB:** whether
  `recalculate_all_posts_votes_and_children`'s aggregation of 1.2B votes spills at
  `work_mem = '4GB'` was not measured. The divide factor does not reach that statement.
- **Cold-cache reads of the split:** all read figures are warm medians.
- **Write mix of the replay:** it reproduces the per-block set of voted posts, not
  each update's exact column changes.
