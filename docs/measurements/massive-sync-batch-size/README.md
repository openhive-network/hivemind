# How many blocks should a massive-sync batch take? (#470)

hivemind's HAF context gave the `MASSIVE_WITHOUT_INDEXES` stage 1000-block batches, so a full massive sync ran
about 111,000 of them, each paying a fixed cost (staging load and reset, the phase calls, the flush, the commit,
`hive.app_next_iteration`). This note measures 1000, 5000 and 10000 blocks per batch, and 100000 as a stand-in for
the heaviest mainnet range.

**Answer: 10000.** It is the fastest of the three in every range measured, it writes no temporary files during
the batches, and its busiest backend peaks at about 1.1 GB. Two things in the batch pipeline were tied to small
batches and are fixed with it: the staging tables were truncated only every 10 calls, and three staging tables
were planned on statistics from some earlier fill, which made the posts phase quadratic in the comments of a
batch. `MASSIVE_WITH_INDEXES` (the last 2M blocks) keeps 1000. The limit is `--massive-sync-batch-blocks`
(`MASSIVE_SYNC_BATCH_BLOCKS`), which sync writes into the context when it starts.

## Setup

- **Host:** steem-4, idle, AMD Ryzen Threadripper 3960X (48 threads), 247 GiB RAM, data on a ZFS dataset (lz4).
- **Data:** HAF's 5M fixture image (`hive/haf/fixture-5m` at HAF 17c8606f, PostgreSQL 18), copied once to a
  dataset; reputation_tracker, HAfAH and hivemind installed from this tree and reputation_tracker synced to
  4,990,000 (`install.sh`), then snapshotted. Every run is a ZFS clone of that snapshot (`run.sh`), so all start
  from the same bytes. No mocks: the runs stop at 4,990,000.
- **PostgreSQL settings** (`50-perf.conf`): steem-20's (`work_mem=64MB`, `hash_mem_multiplier=2`,
  `maintenance_work_mem=4GB`, `random_page_cost=1.01`, `jit=off`, `fsync=off`, `full_page_writes=off`,
  `wal_level=minimal`), with `shared_buffers=16GB` and `log_temp_files=0`.
- **Run:** `hive sync --test-max-block=4990000 --massive-sync-batch-blocks=N`, one run at a time (sequential:
  since #523 that takes `--massive-sync-pipelined=false`, `SYNC_ARGS` of `run.sh`). Massive time is
  from the first batch to the last `[PHASE-SUMMARY]`, timestamped per log line; finalization (index restore and
  the rest, about 150–160 s in every run) is left out. `sampler.py` reads every postgres process's and the hive
  process's `RssAnon`/`VmRSS` once a second, and `activity_sampler.py` host CPU, IO wait and the
  `pg_stat_activity` wait events (added after the results below), through `psql` over the container's local
  socket (set `PGHOST` for a container that admits the user only over TCP); temporary files come from
  PostgreSQL's log.
  `digest.sql` hashes the synced tables at the end. `analyze.py` turns a log into the per-window numbers below.

## Results

Blocks per second over the wall time of each window (between the batch completions at its ends). "Base" is the
code before this change at 1000 blocks; the other columns run this change's code.

| window | base, 1000 | 1000 | 5000 | **10000** | 10000 vs base |
|---|---|---|---|---|---|
| 0–1 M | 42,985 | 43,341 | 102,155 | **123,701** | 2.88× |
| 1–2 M | 25,358 | 25,158 | 36,482 | **42,326** | 1.67× |
| 2–3 M | 17,577 | 17,420 | 23,864 | **26,924** | 1.53× |
| 3–4 M | 3,706 | 3,653 | 3,964 | **4,687** | 1.26× |
| 4–4.99 M | 4,016 | 3,953 | 5,128 | **5,333** | 1.33× |
| **0–4.99 M** | 7,846 (636.0 s) | 7,743 (644.4 s) | 9,515 (524.4 s) | **10,666 (467.9 s)** | **1.36×, −26 %** |

Repeat runs at the same size agree within 2 % (10000: 465.6, 467.9 and 475.3 s across this change's
intermediate versions; 1000: 636.0 and 644.4 s).
Phase sums over the whole run at 1000 → 10000: posts 169 → 141 s, parallel 121 → 97 s, flush 106 → 57 s,
votes 85 → 65 s, load 76 → 59 s.

The light end gains the most, as the issue expected: in 0–1M a 1000-block batch spends 23 ms, of which about
17 ms is the fixed cost. In the fixture's heaviest window (3–5M, 3,700–5,400 blocks/s) the gain is 26–33 %,
most of it in the flush, votes, load and parallel phases.

Memory and temporary files:

| peak | 1000 | 5000 | 10000 | 100000 |
|---|---|---|---|---|
| busiest backend, `RssAnon` | 384 MB | 1,043 MB | 1,100 MB | 2,358 MB |
| all backends, `RssAnon` | 770 MB | 1,314 MB | 1,382 MB | 3,106 MB |
| hive process, `VmRSS` | 290 MB | 662 MB | 697 MB | 1,477 MB |
| temporary files during the batches | 0 | 0 | 0 | 31 files, 2.85 GB (largest 373 MB) |

A backend's `VmRSS` adds the shared buffers it touched (up to 9.8 GB here), so `RssAnon` is what a batch adds.
The 100000 column comes from a run before the ANALYZE fix below; its other columns use this change's code.

Temporary files appear only in finalization (218 files, 1.43 GB, the same in every run): the first one is
written after the last batch. The boundary vacuum of `hive_post_data` ran once in the 1000-block run and not
at all in the others; its dead tuples (about 100 per 10000 blocks here, about one vacuum per 10M blocks on
mainnet) stay far under the 50,000 threshold between two checks.

## The heaviest range: a volume stand-in

The fixture ends at 5M, and the issue's heavy range (18–25M, posts half of each batch) needs a hivemind synced
to 18M on a HAF that holds 25M, which no host had. What makes a batch heavy is its operation count. Counted on
steem-20's HAF (`hive.operations_view`, 100,000 blocks each):

| range | operations | comment + delete | votes | custom_json |
|---|---|---|---|---|
| 4.5 M | 779,506 | 51,642 | 194,371 | 46,660 |
| 7.5 M | 916,852 | 30,222 | 293,422 | 19,640 |
| 20 M | 10,523,210 | 957,614 | 2,687,403 | 1,391,884 |
| 23 M | 10,185,767 | 567,934 | 2,601,120 | 2,269,768 |

A 10000-block batch at 20M holds about 96,000 comment operations: as many as the fixture's 100000-block batch
of 3.3–3.4M (96,563). So the 100000-block runs stand in for 10000 at 20M for everything that grows with the rows
of one batch: memory, temporary files and plan shape. They do not stand in for the per-row cost against
mainnet-sized tables.

They found what 10000 blocks would have hit there. Before the fix, the 3.3–3.4M batch took 501 s, 485 s of it
in the posts phase (the whole batch takes 26.9 s with the fix). `auto_explain` (`profile.sh`) showed nested loops
over staging tables estimated at 1 row: `process_comments_batch`'s result join scanned `_post_batch`'s whole
index once per inserted row (1.1 billion rows removed by the join filter, 456 s), and in another run the wave
loop's anti-join scanned `_post_results` once per `_comment_staging` row (1.9 billion, 424 s and 440 s). These
tables are refilled every call, but their statistics are whatever autovacuum last took. Production's shape plans
the wave anti-join the same way (`Nested Loop (Anti)`, 1 row from `_comment_staging`). With 1000-block batches a
call has a tenth of the rows, so the same plan costs a hundredth. process_posts_from_staging now analyzes
`_comment_staging` after loading it and `_post_results` before each wave, and both batch functions analyze
`_post_batch`, as `load_ops_staging` already did for `_ops_staging` — when the call has at least 1000 comments
(`staging_analyze_min_rows()`). Below that any plan is cheap, and analyzing on every call cost about 16 ms
each (the ANALYZE and the replanning it causes): 715 s instead of 636 s for the 1000-block run, while the
10000-block run did not change.

The 100000-block run's busiest backend peaked at 2.4 GB and the hive process at 1.5 GB, so 10000 at 20M, with
about 1.35× its comment and vote rows, should stay within roughly 3.2 GB and 2 GB. Its batches wrote 31
temporary files (2.85 GB in all, the largest 373 MB): with `work_mem=64MB`, 10000-block batches at 20M will
spill some sorts and hashes to disk.

## The staging reset

The staging functions clear their tables with DELETE and `reset_staging_tables` truncates them every 10 calls.
With 10000-block batches that let a hundred 1000-block batches' worth of dead rows pile up, and every phase
scanning a staging table read them: in 3.53–3.60M the posts phase took 68.2 s at 10000 against 7.0 s at 1000.
The reset now also runs once 10,000 blocks have gone through since the last one, so a 10000-block batch
truncates after itself (about 25 ms), and live sync and 1000-block batches keep their 10 calls. With it alone
the same window takes 6.1 s at 10000.

## Data and crash replay

The synced data was compared across batch sizes on natural keys (`hive_posts` and `hive_votes` ids are drawn in
processing order, so they differ). Accounts and follows are identical; feed, reblogs, permlinks and post
bodies have the same row counts. Two runs at the same size, also across this change's versions, are identical
apart from ids, and so is a 1000-block run killed mid-batch and replayed. A few
results depend on where batch boundaries fall, at any size, because a batch applies all its posts before all its
votes:

| | 1000 | 5000 | 10000 |
|---|---|---|---|
| votes on deleted posts | 2,734 | 2,473 | 2,372 |
| sum of `hive_votes.num_changes` | 48,044 | 47,757 | 47,657 |
| mention notifications (distinct post, src, dst) | 158,236 (124,153) | 139,975 (124,081) | 135,244 (124,065) |
| deleted posts marked paid out | 527 | 517 | 506 |
| posts with a pending payout | 62,229 | 62,033 | 61,772 |

- A vote on a post that is deleted later in the same batch is dropped: the votes phase resolves posts with
  `counter_deleted = 0` after the posts phase has deleted it. Live sync keeps such a vote on the deleted post,
  and `database_api.list_votes` by voter shows it. 362 of 4.39 M votes at 10000.
- Repeated votes inside one batch are folded into one upsert, so `num_changes` counts fewer changes.
- A mention notification is keyed on the post's last-edit block, so each batch boundary an edited post crosses
  adds a duplicate. Larger batches leave fewer duplicates; the distinct mentions differ by 88.
- Payout state of posts both edited and paid out, or deleted and paid out, inside one batch. On mainnet every
  post of the massive range is past its payout.

A 10000-block run killed 3 s into batch 4,510,001–4,520,000 replayed it from `_batch_queue` and finished. Its
data has 62 more `hive_posts` rows than the uninterrupted run, each a third version (`counter_deleted = 2`) of
a post created and deleted in the replayed batch, and 3,784 fewer notifications (not traced). The replay re-applies the
batch's creates and deletes on top of a posts phase that had already committed: the create finds no live row and
inserts one, and the delete then deletes it again. Nothing in that depends on the batch size, but a larger batch
holds more such posts. The 1000-block replay of batch 4,524,001–4,525,000 held none.

#477 removes these effects: [fidelity.md](fidelity.md) has what one block at a time gives, how the batch SQL
now matches it, and the comparisons (1000 against 10000, one block at a time, crash replays).

## Not measured

- The issue's ranges themselves: 5–10M and 18–25M of mainnet, and steem-20's own timing. Mainnet-scale tables
  make each row cost more than here, and the fixed cost per batch on steem-20 was about 0.11 s against 0.02 s
  here. If that 0.11 s is mostly fixed cost, as the issue estimates, 10000-block batches remove about 90 % of
  the ~3 h it adds up to. The live check is the next steem-20 rebuild's massive-sync time against 27.6 h.
- Memory and temporary files at 20M are extrapolated from the 100000-block stand-in, not measured.
