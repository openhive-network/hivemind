# Where `process_posts_from_staging` spends its time in blocks 18–25M (#472)

The posts phase of massive sync (`hivemind_app.process_posts_from_staging`) was 36.7 % of hivemind's busy time
on the 2026-11-12 steem-20 rebuild and about half of each batch in blocks 10–30M. This note profiles it
statement by statement on a copy of mainnet synced to block 19M, separates the cost of the LOGGED tables (#461),
and proposes changes with estimated savings.

**Answer.** One statement dominates, and it is not slow because of table size or WAL:

- The `INSERT INTO hive_posts … RETURNING` of `process_comments_batch`, which joins its RETURNING rows back to
  `_post_batch`, flips between two plans. In the good one (hash join) the whole statement costs 8–9 µs and
  12–19 buffer hits per inserted row. In the bad one (nested loop that re-reads the whole `_post_batch` index for
  every inserted row, 1,000–1,330 buffer hits per row) it is quadratic in the wave size and makes the batch's
  posts phase 8–11× slower. The planner picks the bad plan whenever `_post_batch`'s `pg_class.reltuples` was
  last set by an autovacuum that found the
  table nearly empty (it is filled and `DELETE`d several times per batch), so it estimates 1 row. The root-post
  insert of `process_root_posts_batch` has the same join and the same flip.
- In 19.0–19.5M, 13–18 % of batches ran in the bad state and took 55–68 % of the posts time. On production the
  same bimodality is in every 1M range from 12M on: batches above twice the range's 25th percentile cost
  8,860 s over blocks 0–33M of the 2026-11-15 rebuild, 44 % of its posts time and 20 % of its batch time.
  Keeping `_post_batch` out of autovacuum (experiment F4, one line of DDL) removed the bad state: the posts phase
  of the same 500 batches took 324 s against 616–849 s with the current code (−47 to −62 %), and the whole batch
  1.66 s against 2.25–2.89 s. Truncating the staging tables instead (F2, F3) removes it too, but one `TRUNCATE`
  costs 9.4 ms at 16 GB of `shared_buffers`, growing with `shared_buffers`.
- The LOGGED tables cost nothing measurable in the posts phase on steem-20's WAL settings: with the bad state
  removed, the same 500 batches took 396 s LOGGED and 395 s UNLOGGED, every statement within ±5 % either way,
  while LOGGED writes 11 MB of WAL per batch from the posts phase.
- The run-to-run variance of the flip (of two identical runs here, the second spent 24 % less time in posts) is
  enough to explain the 20–26 % per-batch difference between the 2026-11-12 and 2026-11-15 runs from block 19M;
  #461 is not needed to explain it.

Filed: [#478](https://gitlab.syncad.com/hive/hivemind/-/issues/478) (the `_post_batch` join) and
[#479](https://gitlab.syncad.com/hive/hivemind/-/issues/479) (parsing each root post's `json_metadata` once).

## Setup

- **Host:** steem-19, AMD Ryzen 9 9950X3D (the same CPU as steem-20), 123 GiB RAM, ZFS `haf-pool` on NVMe. Load
  average about 1–2 from a live HAF node on another dataset; the profiling cluster had the CPU and disks to
  itself otherwise.
- **Data:** a ZFS clone of the idle dataset `haf-datadir-20261023-805455da` (HAF at block 111,155,426, cleanly
  shut down), HAF upgraded in place to `df2029cc` (the 2026-11-15 rebuild's HAF; the upgrade needed the
  `KEYAUTH` provider dropped from `hafbe_app` first). hivemind's schema was uninstalled and installed fresh from
  the 2026-11-15 rebuild's image, `hivemind:ba5c5943`, and massive-synced from block 0 to 19,001,000 (3 h 45 min).
  The posts path of ba5c5943 is the same as `develop` (96bf5874): no commit since touches
  `process_posts_from_staging` or the batch functions it calls.
- **PostgreSQL 18** with the dataset's configuration, which is steem-20's except `shared_buffers` (16 GB here,
  40 GB on the 2026-11-15 rebuild): `wal_level=minimal`, `fsync=off`, `full_page_writes=off`,
  `max_wal_size=24GB`, `checkpoint_timeout=60min`, `wal_buffers=128MB`, `pg_stat_statements.track=all`.
  `auto_explain` and `track_wal_io_timing` were added for this work.
- **Samples:** the clone was snapshotted at block 19,001,000 (`@s19`). Each sample rolls back to it, restarts
  PostgreSQL, prewarms the posts tables and their indexes (`pg_prewarm`), resets the statistics, runs the image's
  `sync` until block 19,500,000 (500 batches) and saves `pg_stat_statements`, `pg_stat_wal`, `pg_stat_io` and the
  `[PHASE-SUMMARY]` lines (`tools/run_sample.sh`). The auto_explain sample (`log_analyze`, `log_buffers`,
  `log_wal`, `log_timing`, `log_nested_statements`, JSON) ran 98 batches from the same snapshot. The runs: A1 and
  A2 (current code, LOGGED; A2 was meant as a patched run, but hivemind reinstalls its SQL at startup and the
  patch did not take, which `data/A2/functions.txt` shows, so it is a repeat of A1), U1 (current code, UNLOGGED),
  AE1 (auto_explain), F2/F2U/F3/F4 (the fix experiments, patched SQL mounted into the container).
- **Growth:** during the sync from 4M to 19M, `tools/recorder.sh` dumped and reset `pg_stat_statements` every
  10 minutes (`data/growth.tsv`).
- **Production:** `pg_stat_statements` of the running 2026-11-15 rebuild (blocks 0–33M, read on 2026-11-16) and
  its 33,448 `[PHASE-SUMMARY]` lines from the container log (`data/production/`). Nothing was run on steem-20
  beyond those reads.

## Where the posts phase goes

`process_posts_from_staging` is the posts phase: in the samples its `pg_stat_statements` time is 98 % of the
`posts=` time `[PHASE-SUMMARY]` reports (the rest is fetching its result rows into Python and the commit). Times
below are exclusive (a statement's time minus the statements nested in it). The labels are in
`tools/labels.py`; they cover 98.3 % of the function's time.

Run A1, LOGGED (the current code), blocks 19,001,001–19,500,000, 500 batches, posts phase 794 s:

| statement | calls | excl s | % of posts | ms/batch | rows | µs/row | hit/row | reads | WAL MB |
|---|---|---|---|---|---|---|---|---|---|
| hp_ins_comments | 6226 | 452.1 | 56.9 | 904.2 | 3062452 | 147.6 | 1325 | 3396 | 1587 |
| pb_ins_comments | 6226 | 46.2 | 5.8 | 92.4 | 3062452 | 15.1 | 28 | 19358 | 66 |
| pr_wave_comments | 6226 | 41.7 | 5.2 | 83.3 | 3062452 | 13.6 | 1393 | 5 | 0 |
| hp_ins_root | 500 | 59.0 | 7.4 | 117.9 | 1111573 | 53.1 | 418 | 3556 | 538 |
| pb_ins_root | 500 | 8.7 | 1.1 | 17.4 | 1111573 | 7.8 | 20 | 1348 | 15 |
| pr_root | 500 | 8.4 | 1.1 | 16.9 | 1111573 | 7.6 | 449 | 109 | 0 |
| permlink_ins | 1698 | 38.3 | 4.8 | 76.6 | 3839748 | 10.0 | 22 | 221766 | 1698 |
| tags_5d | 500 | 41.4 | 5.2 | 82.7 | 500 |  | 137574/call | 7568 | 1225 |
| tags_5e | 500 | 9.0 | 1.1 | 18.0 | 500 |  | 32083/call | 1209 | 51 |
| cs_ins | 500 | 21.1 | 2.7 | 42.3 | 4534998 | 4.7 | 7 | 50 | 0 |
| wave_count | 6726 | 19.5 | 2.5 | 39.0 | 6726 |  | 11870/call | 0 | 0 |
| co_ops | 500 | 7.7 | 1.0 | 15.4 | 513864 | 15.0 | 24 | 367 | 184 |
| cs_norm | 500 | 5.6 | 0.7 | 11.3 | 651 | 8656.4 | 20599 | 0 | 0 |
| del_create_pairs | 500 | 4.0 | 0.5 | 8.1 | 500 |  | 7080/call | 0 | 0 |
| edits_5b | 500 | 2.4 | 0.3 | 4.9 | 359775 | 6.7 | 23 | 0 | 0 |
| edits_5c | 500 | 2.3 | 0.3 | 4.5 | 245637 | 9.2 | 35 | 38 | 64 |
| replay_pairs | 1280 | 3.1 | 0.4 | 6.3 | 985 |  | 4842/call | 0 | 0 |
| return_query | 500 | 1.9 | 0.2 | 3.9 | 4534998 | 0.4 | 3 | 0 | 0 |
| del_cs | 500 | 2.0 | 0.3 | 4.1 | 4081674 | 0.5 | 2 | 0 | 0 |
| del_pr | 500 | 1.9 | 0.2 | 3.8 | 4081674 | 0.5 | 2 | 0 | 0 |
| category_ins | 1423 | 2.2 | 0.3 | 4.4 | 21148 | 103.5 | 190 | 1177 | 7 |
| step7e | 500 | 1.2 | 0.2 | 2.5 | 0 |  | 7867/call | 0 | 0 |
| simple_deletes | 500 | 0.7 | 0.1 | 1.3 | 500 |  | 3086/call | 164 | 16 |
| step8_notif | 500 | 0.5 | 0.1 | 0.9 | 0 |  | 3958/call | 0 | 0 |
| posts_fn | 500 | 13.2 | 1.7 | 26.5 | 4534998 | 2.9 | 1134 | 196 | 0 |

`hit/row` is shared-buffer hits per row written or returned; `/call` where the statement returns one row.

Production, blocks 0–33M of the 2026-11-15 rebuild (`pg_stat_statements`, 33,270 batches, posts 19,937 s):

| statement | calls | time (incl.) | % of posts | ms/call | hits/row | read wait | WAL |
|---|---|---|---|---|---|---|---|
| comments: `INSERT INTO _post_results … process_comments_batch` | 212,520 | 9,401 s | 47.2 | 44.2 | 975 | 356 s | 31.5 GB |
| ↳ `WITH inserted AS (INSERT INTO hive_posts …)` (comments) | 212,520 | 6,777 s | 34.0 | 31.9 | 912 | 102 s | 30.9 GB |
| ↳ `INSERT INTO _post_batch` (comments, resolution) | 212,520 | 1,642 s | 8.2 | 7.7 | 33 | 254 s | 0.6 GB |
| roots: `INSERT INTO _post_results … process_root_posts_batch` | 33,270 | 2,842 s | 14.3 | 85.4 | 998 | 116 s | 9.9 GB |
| ↳ `WITH new_posts AS MATERIALIZED (… INSERT INTO hive_posts …)` (roots) | 33,270 | 2,403 s | 12.1 | 72.2 | 965 | 115 s | 9.8 GB |
| `INSERT INTO hive_permlink_data` | 33,270 | 2,861 s | 14.4 | 86.0 | 23 | **1,884 s** | 32.8 GB |
| `process_tags_batch` (Step 5d) | 33,270 | 1,522 s | 7.6 | 45.7 | | 453 s | 23.3 GB |
| `INSERT INTO _comment_staging` | 33,271 | 611 s | 3.1 | 18.4 | 8 | 0 | 0 |
| wave loop `SELECT count(*) FROM _comment_staging …` | 245,790 | 574 s | 2.9 | 2.3 | | 0 | 0 |
| everything else | | ≈ 2,130 s | ≈ 10.7 | | | | |

The two `hive_posts` inserts do 912–965 buffer hits per row on production, against 11–12 for a plain insert of
the same rows (measured on the clone at 1M and 6.9M posts: `EXPLAIN (ANALYZE, BUFFERS)` of 1,000 and 20,000
rows, rolled back). That difference is the bad plan below. The permlink insert is the one statement whose time on
production is mostly reads (1,884 of 2,861 s): its unique index on the permlink text is 9.4 GB at block 33M and
is touched at random. On the quiet clone it reads from the ARC and costs 10 µs per row.

## The `_post_batch` join: two plans, one of them quadratic

`process_comments_batch` fills `_post_batch` with the wave's resolved comments, inserts them into `hive_posts`
and returns the result rows by joining the insert's RETURNING to `_post_batch`
(`hive/db/sql_scripts/hive_post_operations.sql`, `RETURN QUERY WITH inserted AS (INSERT …) SELECT … FROM inserted
ins INNER JOIN hivemind_app._post_batch wm ON wm.author_id = ins.author_id AND wm.permlink_id = ins.permlink_id`).
`process_root_posts_batch` does the same. From the auto_explain sample (`data/AE1/plans/hp_ins_comments.txt`):

Good (the median instance, a 2-row wave; with F4 below every wave of the 500 batches kept this plan):

```
Hash Join  (est rows=1) (actual time=0.360 rows=2 loops=1) hit=1984
  Hash Cond: ((ins.author_id = wm.author_id) AND (ins.permlink_id = wm.permlink_id))
  CTE inserted
    -> Insert on hive_posts  (est rows=5796) … Seq Scan on _post_batch (est rows=5796)
  -> CTE Scan on inserted
  -> Hash -> Seq Scan on _post_batch  (est rows=5796)
```

Bad (the slowest instance, a first wave of 5,049 comments at block 19.07M, 4,697 ms):

```
Nested Loop  (est rows=1) (actual time=4696.078 rows=5049 loops=1) hit=35199919
  Join Filter: ((wm.author_id = ins.author_id) AND (wm.permlink_id = ins.permlink_id))
  Rows Removed by Join Filter: 25487352
  CTE inserted
    -> Insert on hive_posts  (est rows=1) (actual time=48.534 rows=5049) hit=63928
         -> Sort -> Seq Scan on _post_batch  (est rows=1) (actual rows=5049)
  -> CTE Scan on inserted  (est rows=1) (actual rows=5049)
  -> Index Scan using _post_batch_author_permlink_idx on _post_batch  (est rows=1) (actual rows=5049 loops=5049) hit=35120844
```

The insert itself takes 48 ms. The other 4.65 s is the inner index scan, which has no index condition: it reads
all of `_post_batch` through its index for each of the 5,049 inserted rows (5,049² = 25.5 M rows filtered,
6,956 buffer hits per loop).

Why the planner estimates 1 row: `_post_batch` is emptied with `DELETE` at every call (about 13 waves per batch at 19M)
and refilled, so it is mostly dead space. Autovacuum processes it about once a minute, between batches, when it
holds the last wave's few rows in a couple of hundred pages (22 times in U1's 24 minutes), and stores that
density in `pg_class`. The planner scales the stored density to the current size: on a scratch table vacuumed with
3 rows left in 128 pages (`reltuples=3, relpages=128`), 5,000 rows are then estimated at 4
(`tools/trunc_test.sql`). With both
sides of the join estimated at 1 row, the nested loop is the cheapest plan. The estimate stays wrong until an
autovacuum or analyze happens to run while the table is full, and the plan is replanned whenever an autovacuum of
`hive_posts` (about once a minute, #459's thresholds) or of `_post_batch` invalidates it. Hence the stretches:
in run A1 the posts phase went from 0.48 s per batch to 3.8–7.8 s at block 19,052,001 for 19 batches (one in
between ran good), growing as `_post_batch` bloated, then dropped back to 0.40 s.

| run (19.0–19.5M, 500 batches) | posts total | good batches (< 1.2 s) | bad batches | posts if all were good |
|---|---|---|---|---|
| A1, LOGGED | 810 s | 412 × 0.641 s | 88 × 6.206 s (19 stretches) | 321 s (−60 %) |
| A2, LOGGED (repeat of A1) | 616 s | 437 × 0.637 s | 64 × 5.268 s (13 stretches) | 319 s (−48 %) |
| U1, UNLOGGED | 849 s | 418 × 0.655 s | 82 × 7.016 s (17 stretches) | 327 s (−61 %) |
| F2, LOGGED, the 4 staging tables truncated | 396 s | 470 × 0.752 s | 30 × 1.395 s | 376 s |
| F2U, as F2 but UNLOGGED | 395 s | 476 × 0.758 s | 24 × 1.405 s | 379 s |
| F3, LOGGED, only `_post_batch` truncated | 441 s | 440 × 0.801 s | 60 × 1.465 s | 401 s |
| F4, LOGGED, autovacuum off on `_post_batch` | **324 s** | 498 × 0.646 s | 2 × 1.299 s | 323 s |

In F2–F4 the batches over 1.2 s are the heaviest batches of the range (1.2–2.4 s, the same blocks in every
run), not the bad state.

On production the bimodality is the same. Per 1M range of the 2026-11-15 rebuild (`data/production/phase_by_1M.tsv`):

| blocks | posts | batches above 2× the 25th percentile | their mean | the rest's mean | posts at the rest's mean |
|---|---|---|---|---|---|
| 18M | 1,761 s | 190 | 6.19 s | 0.72 s | 723 s |
| 19M | 3,190 s | 162 | 13.53 s | 1.19 s | 1,190 s |
| 20M | 2,064 s | 107 | 10.43 s | 1.06 s | 1,061 s |
| 21M | 1,814 s | 117 | 8.59 s | 0.92 s | 916 s |
| 22M | 1,792 s | 103 | 9.39 s | 0.92 s | 920 s |
| 23M | 1,166 s | 79 | 5.99 s | 0.75 s | 753 s |
| 24M | 1,134 s | 110 | 4.73 s | 0.69 s | 690 s |
| **18–25M** | **12,921 s** | | | | **6,253 s (−52 %)** |
| 0–33M | 20,213 s | | | | 11,357 s (−44 %) |

Production `pg_stat_statements` gives the same size independently: the two `hive_posts` inserts took 9,180 s over
0–33M at 912–965 hits per row; at the good plan's 12–40 hits per row (F4 below: 19 and 12), about 8,800–9,000 s
of it is the bad plan.

The bad batches are the same work done badly, not heavier batches: the same block ranges ran good in one sample
and bad in another (A1 bad at 19,052,001–19,070,000, AE1 good there except 19,068,001–19,070,000).

### Three ways to remove it

Each experiment mounts patched SQL over the image's (`tools/truncate_staging.diff`,
`tools/post_batch_no_autovacuum.diff`) and runs the same 500 batches (per-statement tables in `data/statements.md`):

| run | change | posts phase | comment insert | root insert | outer wave statement | `count(*)` of the wave loop |
|---|---|---|---|---|---|---|
| A1 / A2 | none | 810 / 616 s | 452 / 279 s | 59 / 48 s | 42 / 34 s | 19.5 / 18.4 s |
| F2 | `TRUNCATE` `_post_batch` per call and the other 3 staging tables per batch | 396 s | 26 s | 10 s | 111 s | 13.8 s |
| F3 | `TRUNCATE` `_post_batch` per call | 441 s | 26 s | 10 s | 131 s | 31.6 s |
| F4 | `ALTER TABLE _post_batch SET (autovacuum_enabled = false)`, `DELETE` kept | **324 s** | 26 s | 10 s | 34 s | 18.3 s |

- `TRUNCATE` resets `reltuples` to −1, so the planner estimates from the table's current size, and the insert keeps
  the good plan (16 hits per row). But a `TRUNCATE` of a small unlogged table costs 9.4 ms against 0.06 ms for the
  `DELETE` (`tools/trunc_cost.sql`, 200 rounds): it scans the whole buffer pool to drop the old relation's pages.
  `pg_stat_statements` does not track utility statements here, so the cost shows up in the caller, the outer wave
  statement (+69 to +89 s). At steem-20's 40 GB of `shared_buffers` it would be about 2.5 times larger.
- With autovacuum off, `_post_batch` is never vacuumed or analyzed, so its `reltuples` stays −1 from the table's
  creation (hivemind recreates it at every start, in `massive_sync.sql`), and the planner always estimates from its
  current size. The comment insert kept the good plan in all 500 batches, nothing else got slower, and the table
  stayed small without vacuum (131 heap pages and 33 index pages after 250 batches; dead rows are pruned when
  pages are reused). Whether it stays bounded over a whole sync was not measured.

## Growth with table size

Per 1000-block batch during the sync, from the recorder (`data/growth.tsv`; `hive_posts` held 25.8 M rows at
block 19M). "comment insert" is the `hive_posts` insert of `process_comments_batch`, its share of the posts phase
and its cost per inserted row:

| blocks | batches | posts ms/batch | comment ops/batch | comment insert % | µs/row | hits/row | root insert hits/row | permlink µs/row | permlink hits/row | tags µs/tag | WAL MB/batch |
|---|---|---|---|---|---|---|---|---|---|---|---|
| ≈4M–10.70M | 6655 | 20.2 | 322 | 8.8 | 8.3 | 15.3 | 10.5 | 7.9 | 21.3 | 15.1 | 0.4 |
| 10.70M–13.15M | 2435 | 85.2 | 1321 | 23.4 | 20.6 | 142.0 | 38.0 | 7.6 | 20.7 | 11.5 | 1.5 |
| 13.15M–14.01M | 853 | 275.7 | 4198 | 24.5 | 21.6 | 148.7 | 37.6 | 7.9 | 20.9 | 10.7 | 4.8 |
| 14.01M–14.98M | 966 | 208.6 | 3523 | 16.0 | 13.0 | 65.7 | 21.1 | 8.5 | 21.4 | 10.9 | 4.1 |
| 14.98M–15.86M | 872 | 249.1 | 3418 | 27.4 | 27.8 | 210.0 | 54.5 | 8.8 | 21.4 | 11.0 | 4.0 |
| 15.86M–16.82M | 952 | 192.0 | 3047 | 13.3 | 12.0 | 53.2 | 20.6 | 9.0 | 21.2 | 11.7 | 3.6 |
| 16.82M–17.66M | 840 | 249.8 | 3377 | 16.6 | 18.3 | 116.4 | 40.6 | 9.1 | 20.9 | 12.0 | 4.1 |
| 17.66M–18.34M | 681 | 309.4 | 4326 | 16.5 | 17.9 | 109.6 | 39.4 | 9.3 | 21.1 | 11.5 | 5.3 |
| 18.34M–18.68M | 329 | 924.8 | 6219 | 55.4 | 118.5 | 1065.7 | 275.3 | 9.3 | 21.5 | 12.0 | 7.4 |
| 18.68M–18.95M | 270 | 1232.3 | 8501 | 53.3 | 113.7 | 1010.9 | 282.0 | 9.5 | 21.6 | 11.1 | 10.0 |
| 18.95M–19.00M | 55 | 1605.1 | 8170 | 49.2 | 145.5 | 1289.6 | 328.3 | 10.3 | 21.7 | 11.8 | 9.6 |

- The statements that do not flip cost the same per row from 4M to 19M while `hive_posts` grows to 25.8 M rows:
  the permlink insert 7.6–10.3 µs and 21 hits per row, the tags 10.7–12.0 µs per tag row, the `_post_batch`
  resolution 27–29 hits per row. Their share of the batch grows only with the number of ops per batch (322
  comment ops per batch before 10.7M, 8,500 at 18.7–18.9M).
- The `hive_posts` inserts' cost per row follows the wave size, not the table: 15 hits per row at 4–10.7M (waves of
  about 50 rows), 53–210 at 11–18.3M, 1,010–1,290 from 18.3M (6,200–8,500 comment ops per batch, most of them in
  its first wave). The bad plan's
  cost per row is proportional to the rows in `_post_batch`, so per batch it grows with the square of the
  comment volume, which peaks at 18.5–20M (January 2018).
- On production the permlink insert's index reads grow with the index (`hive_permlink_data_permlink` is 9.4 GB at
  block 33M on the running rebuild) and with the other tenants' pressure on the page cache; on the quiet clone
  they stayed in memory.

## LOGGED versus UNLOGGED

U1 ran the same 500 batches with the 8 tables #461 keeps LOGGED made UNLOGGED first (`ALTER TABLE … SET
UNLOGGED`, 119 s at block 19M). Per statement, exclusive seconds and WAL:

| statement | A1 s | A1 WAL MB | A2 s | U1 s | U1 WAL MB | F2 s | F2 WAL MB | F2U s | F2U WAL MB |
|---|---|---|---|---|---|---|---|---|---|
| hp_ins_comments | 452.1 | 1587 | 279.3 | 482.5 | 0 | 25.8 | 1585 | 24.9 | 0 |
| pb_ins_comments | 46.2 | 66 | 45.9 | 49.8 | 0 | 49.4 | 68 | 52.1 | 0 |
| pr_wave_comments | 41.7 | 0 | 34.1 | 42.1 | 0 | 110.8 | 0 | 111.2 | 0 |
| hp_ins_root | 59.0 | 538 | 47.7 | 58.6 | 0 | 9.7 | 537 | 9.4 | 0 |
| pb_ins_root | 8.7 | 15 | 8.8 | 9.1 | 0 | 8.5 | 16 | 8.7 | 0 |
| permlink_ins | 38.3 | 1698 | 38.7 | 40.4 | 0 | 38.0 | 1698 | 37.6 | 0 |
| tags_5d | 41.4 | 1225 | 41.5 | 40.5 | 196 | 42.4 | 1225 | 40.9 | 197 |
| tags_5e | 9.0 | 51 | 9.0 | 9.1 | 37 | 7.6 | 51 | 7.4 | 37 |
| cs_ins | 21.1 | 0 | 21.3 | 21.9 | 0 | 19.7 | 0 | 19.6 | 0 |
| wave_count | 19.5 | 0 | 18.4 | 19.7 | 0 | 13.8 | 0 | 13.8 | 0 |
| co_ops | 7.7 | 184 | 7.7 | 7.7 | 0 | 7.9 | 182 | 7.8 | 0 |
| posts_fn | 13.2 | 0 | 13.2 | 13.7 | 0 | 14.6 | 3 | 14.5 | 3 |

- The statements that do not flip take the same time LOGGED and UNLOGGED (A1 and A2 against U1: permlink
  38.3/38.7 against 40.4 s, `_post_batch` resolution 46.2/45.9 against 49.8 s, tags 41.4/41.5 against 40.5 s,
  `_comment_staging` 21.1/21.3 against 21.9 s). The `hive_posts` inserts differ by the number of bad batches
  each run happened to get.
- LOGGED, the posts phase writes 5.45 GB of WAL in 500 batches (10.9 MB per batch): the permlink insert 1.70 GB,
  the comment `hive_posts` insert 1.59 GB, the tags 1.28 GB, the root insert 0.54 GB. The whole cluster wrote
  17.5 GB LOGGED against 1.5 GB UNLOGGED (the votes and the other phases account for the rest). With
  `fsync=off`, `full_page_writes=off` and `wal_level=minimal`, writing it costs no measurable time, in line with
  #460's 0.81 s per GB for the single-connection posts phase (≈ 4 s over these 500 batches, under the noise).
- With the bad state removed, the comparison is clean: F2 against F2U, 396 s against 395 s of posts phase; the
  comment insert 25.8 against 24.9 s, the permlink insert 38.0 against 37.6 s, the resolution 49.4 against 52.1 s,
  the tags 50.0 against 48.3 s.

## Other statements

- **Step 5d/5e tags** (6.3 % in A1): `hivemind_app.safe_parse_jsonb_tolerant(op_body->>'json_metadata')` is
  PL/pgSQL with an `EXCEPTION` block, so every call opens a subtransaction, and Step 5d references its result four
  times from a flattened subquery. The auto_explain excerpt counts 5,981–6,239 calls per batch for about 2,200 root
  posts. On the 2,697 root posts of one batch (`tools/bench_tags.sql`, median of 7 runs), Step 5d's query takes
  35.8 ms as written, 14.6 ms with `base` fenced so the function runs once per post, and 19.3 ms parsing once but
  checking validity with `pg_input_is_valid` before the cast (two parses cost more than the subtransaction).
  Parsing once saves about 21 ms per batch at 19M.
- **The `_post_batch` resolution** (`INSERT INTO _post_batch`, 6.9 % with roots): index lookups only, about 25
  hits per row: the parent's account and permlink by name, the parent post by `hive_posts_ux1`, the author and the
  permlink by name. The permlinks it looks up by text were inserted or found by Step 3 a moment before; resolving
  their ids once there would save two text-index lookups per op (about 3 % of the phase in AE1's node times).
- **Staging-table scans** (`count(*)` of the wave loop 2.5 %, `_delete_create_pairs` 0.5 %, the parent
  normalization 0.7 %): sequential scans of `_comment_staging` and `_post_results`, which are also emptied with
  `DELETE` and read 6,115 pages for 10,140 rows in the slowest instance. Truncating them once per batch (F2) cut
  the `count(*)` from 19.5 to 13.8 s per 500 batches (11 ms per batch), less than the three `TRUNCATE`s per batch
  cost (28 ms at 16 GB). Not worth a change on its own.
- **The permlink insert** (4.8 % here, 14.4 % on production): `ON CONFLICT DO NOTHING` into the unique text index;
  36 % of the rows conflict (permlinks of edits and of parents). On production it waits on reads; nothing in the
  statement's plan is wrong.

## Autovacuum (intake note 3)

During U1 (24 minutes), autovacuum processed `hive_posts` 24 times, scanning 4.53 M heap pages in total, 11 of
the runs with an index pass; `hive_votes` 24 times (2.09 M pages); the staging tables about once a minute each. In
A1's `pg_stat_io`, autovacuum workers read 2.74 M blocks (68 GB) against 3.58 M blocks (29 GB) for the client
backends. On the clone those reads came from the ZFS ARC; on steem-20, with nine other apps in massive sync, they
compete for the same page cache and disks as the permlink insert's reads. They are not in the posts session's own
time, but autovacuum is what sets `_post_batch`'s misleading density and what invalidates the plans that then flip.

## Proposed changes

| # | change | saving (estimate) | issue |
|---|---|---|---|
| 1 | Keep `_post_batch`'s row estimate truthful so the RETURNING join stays a hash join: `ALTER TABLE hivemind_app._post_batch SET (autovacuum_enabled = false)` after its `CREATE` (F4), or an equivalent that does not cost a `TRUNCATE` per call | Clone, 19.0–19.5M: posts phase −292 to −525 s per 500 batches (−47 to −62 %), batch time −26 to −43 %. Production, from its own per-batch times and `pg_stat_statements`: ≈ 6,670 s over 18–25M (52 % of the posts phase there), ≈ 8,860 s over 0–33M (44 % of posts, 20 % of batch time, ≈ 2.5 h of the 26.2 h). It grows with the square of the wave size, so it would be larger with #470's bigger batches | [#478](https://gitlab.syncad.com/hive/hivemind/-/issues/478) |
| 2 | Parse each root post's `json_metadata` once in Steps 5d/5e | ≈ 21 ms per batch at 19M (Step 5d's parsing 35.8 → 14.6 ms), about 3–4 % of the posts phase once #1 is in (tags are 15.7 % of F4's posts phase); on production about a quarter of Step 5d's 1,522 s over 0–33M, ≈ 380 s | [#479](https://gitlab.syncad.com/hive/hivemind/-/issues/479) |

Not proposed:

- `TRUNCATE` instead of `DELETE` for the staging tables: it fixes the estimate (F2, F3) but costs 9.4 ms per
  `TRUNCATE` at 16 GB of `shared_buffers`, more than it saves anywhere except in the bad plan, which #1 removes
  for free.
- Resolving permlink ids once in Step 3 for the batch functions: about 3 % of the phase in AE1's node times, and it
  reshapes the batch functions' inputs.
- Anything for the LOGGED tables (no measurable cost) or for the permlink insert's reads (production-only, from page
  cache pressure; the statement's plan is right).

## What was not analysed

- Blocks 20–25M were not sampled on the clone: the samples cover 19.0–19.5M, the peak of production's posts time
  per batch. 18–25M is covered by production's per-batch times and `pg_stat_statements`, which show the same
  bimodality in every 1M range.
- The clone is about 2× faster than production in the good state (0.64 s against 1.19 s per batch at 19M), from
  the other tenants' load on steem-20 and its larger page-cache pressure. The savings above are scaled from
  production's own numbers where they are given in production seconds.
- Each sample starts from a fresh session, with the staging tables recreated by hivemind's startup (it reinstalls
  `massive_sync.sql`, which drops and recreates them). A sync running for hours starts the bad stretches from a
  more bloated `_post_batch`; the main sync's last 25,000 blocks averaged 1.0–1.4 s per batch against A1's 0.57 s
  for its first 25,000.
- Blocks beyond 33M: the production split covers 0–33M only.
- F4 ran 500 batches. That `_post_batch` stays small without vacuum over a whole sync (about 1.4 M waves) was not
  measured; #478 asks for it.

## Files

- `tools/run_sample.sh` — one sample from the `@s19` snapshot (`HM_MOUNTS` mounts patched SQL into the hivemind
  container). `tools/recorder.sh`, `tools/stopper.sh` — the growth recorder and the stop at block 19,000,000.
  `tools/pss_dump.sql`, `tools/pss_queries.sql`, `tools/sizes.sql` — what they record.
- `tools/ae_parse.py` — per-statement and per-node tables and the median/slowest plans from an auto_explain jsonlog;
  `tools/ae_excerpt.py` — one batch's entries. `tools/labels.py` — the statement labels. `tools/stmt_table.py`,
  `tools/growth.py`, `tools/phase.py`, `tools/states.py` — the tables above.
- `tools/truncate_staging.diff` — experiment F2's change (F3 is its `hive_post_operations.sql` half);
  `tools/post_batch_no_autovacuum.diff` — experiment F4's. `tools/trunc_test.sql` — the estimate after a vacuum of
  a nearly empty table and after a `TRUNCATE`. `tools/trunc_cost.sql` — the cost of one `TRUNCATE` against one
  `DELETE`. `tools/bench_tags.sql` — the json_metadata parse benchmark.
- `data/A1`, `data/A2`, `data/U1`, `data/F2`, `data/F2U`, `data/F3`, `data/F4` — each sample's `pg_stat_statements`,
  query texts, `[PHASE-SUMMARY]` lines and `pg_stat_wal`/`pg_stat_checkpointer`/`pg_stat_io` (`data/U1/autovacuum.log`:
  the autovacuum log entries of that run); `data/statements.md` — the per-statement tables.
- `data/AE1` — auto_explain of 98 batches: `statements.tsv`, `nodes.tsv` (exclusive time and buffers per plan node),
  `plans/*.txt` (median and slowest instance of each statement) and `excerpt.jsonl.gz` (every plan of the posts
  phase of batches 19,067,001 (good) and 19,068,001 (bad), 12,482 entries).
- `data/growth.tsv`, `data/sync_sizes.tsv`, `data/sync_phase.txt.gz` — the sync from 4M to 19M. `data/production/` —
  the 2026-11-15 rebuild's `pg_stat_statements` (hivemind, top 60), per-batch phase times and their 1M split.
