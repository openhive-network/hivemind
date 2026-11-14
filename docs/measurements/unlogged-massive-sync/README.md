# Do massive sync's UNLOGGED tables pay for themselves? (#460)

On an initial sync, massive sync makes 8 tables UNLOGGED (`hive_votes`, `hive_post_data`, `hive_posts`,
`hive_permlink_data`, `hive_post_tags`, `hive_accounts`, `hive_reblogs`, `hive_mentions`). Before it restores
indexes, it makes them LOGGED again (`set_logged_table_attribute`, `DbState.ensure_indexes_are_disabled` /
`ensure_indexes_are_enabled`). This note measures what that saves and what it costs.

**Answer: it does not pay for itself. Keep the tables LOGGED for the whole sync.** On the same host and data,
LOGGED from the start writes 69 GB of WAL that UNLOGGED skips, and it is 48–73 s slower while the batches run.
The `SET LOGGED` rewrite at the end costs 115–130 s, so LOGGED from the start reaches the end 42–81 s sooner
(5–15 %). Extrapolated to the 2026-11-12 steem-20 rebuild, LOGGED from the start adds about 765 s to the
batches (≈ 730 GB of WAL), while UNLOGGED costs 1,034 s of `SET LOGGED` plus the 2–3 min vacuum #459 needs.
LOGGED from the start also removes the crash-wipe risk.

## Production baseline: the 2026-11-12 steem-20 rebuild

- **Host:** steem-20, AMD Ryzen 9 9950X3D (32 threads), 121 GiB RAM, ZFS pool `haf-pool` striping 2 × Crucial T710 4 TB
  NVMe (recordsize 128K, compression on).
- **Software:** hivemind `066eece7`, PostgreSQL 18.6. HAF and about 10 other HAF apps synced on the same
  cluster at the same time. HAF itself was replaying from block 0 until about 21:30 UTC on 11-12.
- **PostgreSQL settings** (all from the configuration file): `wal_level=minimal`, `max_wal_senders=0`, `fsync=off`,
  `full_page_writes=off`, `max_wal_size=24GB`, `checkpoint_timeout=3600`, `checkpoint_completion_target=0.9`,
  `wal_compression=pglz`, `wal_buffers=128MB`, `shared_buffers=16GB`. `synchronous_commit` is `on`, and hivemind
  sets it `OFF` on its connection. hivemind's attempt to turn `fsync`/`full_page_writes` off was refused
  (`haf_admin` is not superuser), but both were already off in the configuration.

Massive sync from block 1 to 111,643,131 took 93,580 s (26.0 h; `SYNC_TIMING_JSON`). The `[PHASE-SUMMARY]` totals
add up to 94,206 s: posts 36.7 %, votes 22.8 %, parallel 14.8 %, load 14.0 %, vacuum 4.7 %, flush 3.6 %, the
rest under 1.5 % each.

| blocks | wall clock (UTC) | phase total | blocks/s | posts | votes | parallel | flush |
|---|---|---|---|---|---|---|---|
| 0–10 M | 11-12 08:01 | 1,145 s | 8,730 | 265 | 253 | 252 | 49 |
| 10–20 M | 08:21 | 14,913 s | 671 | 7,629 | 2,273 | 2,311 | 591 |
| **20–30 M** | 12:26 | **22,281 s** | **449** | 10,264 | 4,334 | 3,920 | 851 |
| 30–40 M | 18:33 | 9,558 s | 1,046 | 3,053 | 2,955 | 1,440 | 375 |
| 40–50 M | 21:11 | 13,428 s | 745 | 4,468 | 2,495 | 1,338 | 273 |
| 50–60 M | 11-13 00:55 | 7,924 s | 1,262 | 2,261 | 2,123 | 1,064 | 266 |
| **60–70 M** | 03:07 | **7,973 s** | **1,254** | 2,255 | 2,024 | 1,164 | 263 |
| 70–80 M | 05:19 | 5,018 s | 1,993 | 1,323 | 1,408 | 772 | 203 |
| 80–90 M | 06:42 | 4,659 s | 2,146 | 1,300 | 1,357 | 700 | 190 |
| 90–100 M | 08:00 | 4,027 s | 2,483 | 1,017 | 1,201 | 552 | 165 |
| 100–111.6 M | 09:07 | 3,279 s | 3,551 | 777 | 1,061 | 443 | 192 |

Then `Converting 8 tables to LOGGED` took 1,034.2 s: `hive_votes` 1,022.9 s, `hive_post_data` 712.8 s,
`hive_posts` 311.5 s, `hive_permlink_data` 135.1 s, `hive_post_tags` 88.6 s, `hive_reblogs` 11.2 s, `hive_accounts`
2.6 s, `hive_mentions` 0.5 s. The UNLOGGED conversion at the start took 0.2 s, because the tables were empty.

What the rebuild wrote. These figures come from `pg_stat_user_tables` since the stats reset at 11-12 08:01, so
they include finalization and about 18 h of live sync:

| table | inserted | updated (HOT) | heap + TOAST | kept PK / unique indexes |
|---|---|---|---|---|
| hive_votes | 1,199.4 M | 2.3 M | 130 GB | 25.1 + 35.2 GB |
| hive_post_data | 137.2 M | 5.7 M | 98 GB | 2.9 GB |
| hive_posts | 137.2 M | 446.5 M (201.9 M) | 67 GB | 2.9 + 4.0 GB |
| hive_permlink_data | 133.0 M | 0 | 11 GB | 2.8 + 9.6 GB |
| hive_post_tags | 134.3 M | 0 | 4.6 GB | |
| hive_reblogs | 17.0 M | 0 | 1.0 GB | |
| hive_accounts | 2.6 M | 140.0 M (108.3 M) | 0.4 GB | |

The cluster's WAL during the rebuild, from its checkpoint log: HAF's replay wrote 350–440 GB of WAL per hour with
28–35 checkpoints per hour until 21:30. After that the other apps wrote 25–150 GB per hour. Over the whole
window there were 572 checkpoints, 555 of them requested by WAL volume. hivemind's tables, being UNLOGGED, added
no WAL. PostgreSQL did not crash or restart during the massive sync. It restarted cleanly at 11-13 20:42, after
the tables were LOGGED again.

## A/B measurement: LOGGED vs UNLOGGED on the same host and data

A mainnet-range A/B of hivemind itself would need a HAF copy at blocks 20–30 M and 60–70 M on a quiet host,
plus a hivemind synced up to the start of each range. That is many hours of replay and sync, and none was
available to this workflow. It is filed as #462, held for the operator. What was measured instead is the part of
massive sync that UNLOGGED changes: the writes into the converted tables. The benchmark uses the tables' real
DDL with the indexes massive sync keeps (PK and unique constraints), the write pattern of a 1000-block batch,
the same PostgreSQL major version and the same WAL settings.

- **Host:** steem-4, idle, AMD Ryzen Threadripper 3960X (48 threads), 247 GiB RAM. Data on a ZFS dataset striping
  2 × XPG GAMMIX S50 Lite NVMe (recordsize 128K, lz4), the same layout as steem-20's `haf-pool`.
- **PostgreSQL 18.7** (`postgres:18`), with steem-20's settings: `wal_level=minimal`, `max_wal_senders=0`,
  `fsync=off`, `full_page_writes=off`, `max_wal_size=24GB`, `checkpoint_timeout=3600`,
  `checkpoint_completion_target=0.9`, `wal_compression=pglz`, `wal_buffers=128MB`, `shared_buffers=16GB`,
  `synchronous_commit=off` on the writers, autovacuum on (off for `hive_post_data`, as massive sync sets it).
- **Workload** (`schema.sql`): 1,200 batches. Each batch has 4 vote workers, each upserting 25,000 votes with
  `ON CONFLICT ON CONSTRAINT hive_votes_voter_id_author_id_permlink_id_uk DO UPDATE` (the
  `--massive-vote-workers` default). One posts worker inserts 11,400 permlinks, posts and post bodies of
  32–1,184 characters, then updates 20,000 recent posts. That totals 120 M votes, 13.7 M posts and 24 M post
  updates, a tenth of mainnet, with mainnet's ratio of votes to posts. At the end the tables hold 37–40 GB, more
  than `shared_buffers`. UNLOGGED runs then `ALTER TABLE … SET LOGGED` on the 4 tables in parallel, as
  `set_logged_table_attribute` does.
- `run.sh` runs the vote workers and the posts worker concurrently. `run2.sh` runs the votes phase and then the
  posts phase, as a hivemind batch does, and times each one. WAL comes from `pg_stat_wal`, checkpoints and
  their writes from `pg_stat_checkpointer`, and physical disk writes from `/proc/diskstats` on the two NVMe
  devices, after ZFS compression.

| run | mode | votes phase | posts phase | batches total | SET LOGGED | **end to end** | WAL | requested checkpoints | checkpointer writes | disk writes |
|---|---|---|---|---|---|---|---|---|---|---|
| concurrent 1 | UNLOGGED | | | 406.7 s | 127.5 s | **534.3 s** | 0.0 GB | 0 | 0 | 8.4 + 28.0 GB |
| concurrent 2 | LOGGED | | | 453.9 s | — | **453.9 s** | 68.7 GB | 5 | 38.1 GB | 45.9 GB |
| concurrent 3 | LOGGED | | | 452.2 s | — | **452.2 s** | 68.7 GB | 5 | 38.1 GB | 45.7 GB |
| concurrent 4 | UNLOGGED | | | 403.2 s | 130.2 s | **533.4 s** | 0.0 GB | 0 | 0 | 8.1 + 29.1 GB |
| sequential 1 | LOGGED | 368.0 s | 398.8 s | 766.8 s | — | **766.8 s** | 40.2 + 28.4 GB | 2 + 3 | 33.0 GB | 49.1 GB |
| sequential 2 | UNLOGGED | 317.1 s | 380.0 s | 697.1 s | 115.2 s | **812.3 s** | 0.0 GB | 0 | 0 | 15.3 + 22.0 GB |
| sequential 3 | UNLOGGED | 317.2 s | 372.4 s | 689.6 s | 114.5 s | **804.0 s** | 0.0 GB | 0 | 0 | 12.7 + 22.8 GB |
| sequential 4 | LOGGED | 366.4 s | 399.8 s | 766.2 s | — | **766.2 s** | 40.2 + 28.4 GB | 2 + 3 | 34.1 GB | 49.8 GB |

A sensitivity pair used PostgreSQL's defaults, `fsync=on` and `full_page_writes=on`, which a HAF
cluster that keeps them would run with. It is one run each, `run.sh`, with the other settings unchanged:

| mode | batches total | SET LOGGED | **end to end** | WAL | full-page images | `wal_buffers_full` | requested checkpoints | disk writes |
|---|---|---|---|---|---|---|---|---|
| UNLOGGED | 410.8 s | 131.1 s | **541.9 s** | 0.0 GB | 0 | 0 | 0 | 8.3 + 30.4 GB |
| LOGGED | 505.0 s | — | **505.0 s** | 77.1 GB | 2.08 M | 296,705 | 5 | 60.5 GB |

With full-page writes, LOGGED makes the batches 94.3 s (+23 %) slower. It still finishes 36.9 s (6.8 %)
sooner. Scaled to mainnet, that is about 1,000 s of batch time against 1,180–1,210 s of conversion and vacuum,
roughly break-even. On such a cluster, the crash-restart risk alone decides the question.

Repeat runs agree within 1–2 %. Means:

- **Concurrent:** LOGGED makes the batches 48.1 s (+11.9 %) slower. The conversion it avoids costs 128.9 s, so
  LOGGED finishes 80.9 s (15 %) sooner.
- **Sequential:** LOGGED makes the votes phase 50.1 s (+15.8 %) slower and the posts phase 23.1 s (+6.1 %)
  slower. The conversion costs 114.8 s, so LOGGED finishes 41.6 s (5.1 %) sooner.
- **WAL per row written:** 335 B per vote (the heap tuple plus two B-tree entries, with page splits) and
  2,077 B per post (post, body, permlink and 1.75 updates). The cost is 1.25 s of votes-phase wall time per GB
  of WAL with 4 workers, and 0.81 s per GB in the single-connection posts phase.
- **Checkpoints:** 5 extra requested checkpoints per 68.7 GB of WAL (`max_wal_size=24GB`). They write
  33–38 GB of hivemind pages that UNLOGGED leaves to eviction or to the rewrite. Physical disk writes come to
  45.7–49.8 GB with LOGGED against 35.5–37.3 GB with UNLOGGED (including its rewrite), about 30 % more. Over
  the run that is 64–101 MB/s, well under what the NVMe pair sustains.

The votes and posts slowdowns match #415's 5M fixture A/B (votes +14 %, flush +7.5 %, the other phases within
±4 %). Both are workloads with little work per row, where the WAL record is a large share of each row's cost.

## Extrapolation to a full sync

WAL is a fixed cost per row written: building and CRC-ing the record and copying it to the WAL buffers. It
does not grow with the rest of the per-row work, so the extrapolation scales the measured seconds by rows, not
by percentages. The production votes phase handled 1,199 M votes in 21,484 s (56 k votes/s). The benchmark
handled 378 k votes/s. The per-vote work production does on top of the write (staging joins, unique-key
lookups in a 35 GB index) does not add WAL.

| | rows on mainnet | WAL if LOGGED | added batch time |
|---|---|---|---|
| votes phase | 1,199.4 M votes (×10.0 the benchmark) | 402 GB | 501 s |
| posts phase | 137.2 M posts (×10.0) | 285 GB | 232 s |
| tables not in the benchmark (`hive_post_tags`, `hive_reblogs`, `hive_mentions`, `hive_accounts` updates) | 134 M + 17 M + 0.6 M rows, 140 M updates | ≈ 40 GB | ≈ 33 s at 0.81 s/GB |
| **total** | | **≈ 730 GB** (7.8 MB/s over 26 h) | **≈ 765 s (12.8 min)** |

The cost of UNLOGGED on the same rebuild: 1,034 s of `SET LOGGED` plus the vacuum that restores the visibility
map the rewrite empties (#459, 2–3 min measured), about **1,180–1,210 s**. The steem-4 conversion
(115–130 s for 37 GB, so about 1,300 s scaled to steem-20's 395 GB of heap and kept indexes) agrees with the
1,034 s measured on steem-20.

**Net: LOGGED from the start reaches live about 7 min sooner,** −0.5 % of the 26 h sync. The estimate has an
upper bound. If WAL cost grew with the per-row work instead, so #415's relative slowdowns applied to the
production phases (votes +14–16 % of 21,484 s, flush +7.5 % of 3,419 s), LOGGED would add 3,260–3,690 s:
34–42 min more than the conversion, +2.2–2.7 % of the sync. The benchmark contradicts that assumption. Its
votes phase is 6.7× lighter per row than production's, yet its relative slowdown is the same as on the 5M
fixture. Either way, the difference is within ±2.7 % of a full sync.

What else changes besides time:

- **WAL volume and checkpoints:** about 730 GB of WAL and about 53 more requested checkpoints. steem-20's
  cluster wrote 7.46 TB of WAL with 555 requested checkpoints from 11-12 08:01 to 11-14 04:23, so that is about +10 %.
  During HAF's own replay (blocks 0–40 M of this rebuild), hivemind's WAL competes with about 110 MB/s of HAF
  WAL. The benchmark ran on an otherwise idle host, which is the main uncertainty of the extrapolation and
  the reason for the held mainnet A/B.
- **Crash restarts:** a PostgreSQL crash restart truncates UNLOGGED tables. A backend killed by the OOM
  killer, a segfault, `docker kill`, or a stop that escalates to SIGKILL all count. Then
  `_check_unlogged_data_consistency` restarts the sync from block 0, losing on average half of the 26 h. With
  LOGGED tables, crash recovery replays the WAL and hivemind continues from its last committed batch. Even with
  `fsync=off` that holds as long as the OS keeps running. Each 1 % chance of a crash restart during the sync
  costs about 8 min in expectation. No crash restart happened in this rebuild, but HAF's PostgreSQL received 7
  fast-shutdown requests (clean ones) on steem-20 in the 19 h after it.
- **Side effects of the rewrite, which removal also deletes:** the 17 min serial step before index creation;
  the emptied visibility map that left the API at p50 1.4 s until a vacuum (#459); the synchronized seq scan
  that scattered `hive_votes` (#457/#458); and the BM25 index drop that must come before the conversion.

## Reconciling earlier measurements

- **#339 (hbt5, 2026-08): 6,566 s round trip.** That run measured the non-initial path: `SET UNLOGGED` on full
  tables (3,169 s) plus `SET LOGGED` (3,397 s) for a one-week catch-up. Since #339, the conversion runs only on
  an initial sync (`DbState.is_initial_sync()`). `SET UNLOGGED` now runs on empty tables (0.2 s), so the round
  trip is only `SET LOGGED`: 727 s on #415's test node at block 111.04 M and 1,034 s on steem-20. hbt5 rewrote
  larger tables on other hardware: `schema.py` still cites `hive_votes` at about 319 GB, against 130 GB on
  steem-20. The available logs do not separate those two causes.
- **#339: WAL waits were ≤ 2 % of with-indexes processing.** This agrees with this note: WAL is a small fixed
  cost per row, smaller than the rewrite that avoids it.
- **#415 (5M fixture, `wal_level=minimal`, `fsync` on): LOGGED batches +2.7 % (concurrent pair) / +4.1 %
  (sequential pair) against a 5.5 s conversion. Two identical runs differed by 9 %.** At 5 M blocks the tables
  are tiny, so the conversion costs almost nothing while the per-row WAL cost is the same. The 5M fixture is
  therefore the setting most favourable to UNLOGGED, and its result does not carry over to mainnet. At mainnet,
  the conversion grows with the final table sizes (395 GB), and the per-row WAL cost becomes a smaller share
  of the heavier per-row work.

## Recommendation

Filed as #461. Remove the UNLOGGED conversion and keep all 8 tables LOGGED for the whole sync. Keep the staging tables
(`_ops_staging`, `_vote_upsert`, `_post_batch`, …) UNLOGGED: they are rebuilt every batch and are not part of
this conversion. No per-table exception is worth keeping. `hive_votes` is the largest WAL producer (402 GB) and
also the largest conversion (1,023 s), and the other tables convert in its shadow. Keeping only `hive_votes`
UNLOGGED would keep the whole 17 min critical path and the crash-wipe risk for the 501 s it saves.

The change: drop `set_logged_table_attribute(…, False)` and the BM25 drop that exists only for it from
`ensure_indexes_are_disabled`. Drop the `SET LOGGED` from `ensure_indexes_are_enabled`, which becomes a
no-op on LOGGED tables. Keep a one-time `SET LOGGED` for databases still mid-sync with UNLOGGED tables when
they upgrade. Remove `_check_unlogged_data_consistency` and its call (`hive/indexer/sync.py`). The shutdown path
there restores LOGGED and indexes before exit to protect UNLOGGED tables, so revisit it too. Update `MASSIVE_WITHOUT_INDEXES_THRESHOLD_BLOCKS`'s comment in
`hive/conf.py`, the comment in `db_state.py`, and `CLAUDE.md`'s description of massive sync. Then compare the
next steem-20 rebuild's `[PHASE-SUMMARY]` per range with the table above.

## Reproducing

`schema.sql`, `run.sh` and `run2.sh` are in this directory. Start PostgreSQL 18 with the settings above in a
container named `pg460` with a database `bench`. Then run, for example,
`for m in UNLOGGED LOGGED LOGGED UNLOGGED; do ./run.sh $m 1200; done`. Each run drops and recreates the tables. `results.txt` holds the raw output of every run above.
