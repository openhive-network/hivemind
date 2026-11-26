# hive_votes in post order

Massive sync writes votes in block order. A post collects its votes over about a week,
mixed in with every other vote of that week, so they end up about 0.67 heap pages apart.
Reading a post's votes (`top_votes`, `observer_vote`, `active_votes`) then reads about one
heap page per vote. That made `hive_votes` the table with the most physical reads on
api.syncad.com.

## What a sync from scratch does

When an initial sync first restores its registered indexes, the `hive_votes` restore thread
rewrites the table in `(post_id, voter_id)` order before it restores that table's other
indexes (`DbState._order_hive_votes_by_post`). The rewrite is one transaction, under the
`ACCESS EXCLUSIVE` lock `CLUSTER` would take:

1. A parallel query sorts the table into an UNLOGGED copy:
   `CREATE UNLOGGED TABLE hivemind_app.__hive_votes_sorted AS SELECT * FROM hivemind_app.hive_votes ORDER BY post_id, voter_id`,
   with `max_parallel_workers_per_gather` set to `--finalization-workers` (default 4).
   `CLUSTER` sorts on one process.
2. `hivemind_app.copy_back_hive_votes` drops the table's indexes and the constraints they
   back (the primary key and the `(voter_id, author_id, permlink_id)` unique constraint;
   the other registered indexes are still dropped at this point), truncates the table,
   copies the sorted rows back in heap order, and rebuilds the indexes and constraints from
   the copied heap.
3. It builds `hive_votes_post_id_voter_id_idx` from its registered command, which is
   `CREATE INDEX IF NOT EXISTS`, marks it as the table's clustering index
   (`ALTER TABLE ... CLUSTER ON`) and drops the copy.

The restore that follows skips the index from step 3, because it already exists. Then the
thread runs `VACUUM (FREEZE, ANALYZE)` on the table, to set the visibility map and collect
statistics. When the restore goes straight into finalization (no massive batch follows
it), hivemind builds the BM25 index on another thread at the same time, and the vacuum waits
for that build to end. A BM25 build that started before the rewrite committed holds the xmin
horizon below the rewritten rows, so a vacuum running beside it could neither freeze them nor
mark their pages all-visible. The other tables restore their indexes in parallel threads, so
they don't wait for this step.

The sync log reports the step's times:

```
[MASSIVE] Ordered hivemind_app.hive_votes by post_id in <s> (parallel sort <s>, copy-back <s>, index and constraint rebuild <s>, hive_votes_post_id_voter_id_idx <s>)
[MASSIVE] Vacuumed hivemind_app.hive_votes after its ordering in <s>, after waiting <s> for the BM25 build; <n> of <m> pages all-visible
```

If the vacuum cannot mark the pages all-visible (another app's snapshot is older than the
rows, #459), the VisibilityWatch of live sync vacuums the table again later.

If the process stops before the rewrite commits, the transaction rolls back: the table, its
indexes and the missing mark are as before, and the next start rewrites it again. Once the
rewrite has committed, `pg_index.indisclustered` on `hive_votes_post_id_voter_id_idx` shows
that it is done, and the next start skips it. The step runs only during an initial sync
(`DbState.is_initial_sync`). A catch-up massive sync on a node that has already finished
one leaves the table unchanged.

New votes keep arriving in block order at the end of the table. Votes on posts older than
about a week no longer change, and the last week's votes are about 0.1% of the table, so
the ordering stays good without re-clustering.

## Cost

These numbers come from a ZFS clone of api.syncad.com's replayed database (PG 18.7,
`maintenance_work_mem` 4 GB, 4 parallel maintenance workers, 2026-11-16):

| `WHERE post_id = X ORDER BY abs(rshares) DESC, voter_id` | pages/call | cold ms (avg / p95) |
|---|---|---|
| block order, posts >30 days old | 213 | 8.85 / 22.5 |
| block order, posts of the last 7 days | 91 | 1.53 / 6.3 |
| post order, posts >30 days old | 8.5 | 0.85 / 1.42 |
| post order, posts of the last 7 days | 6.6 | 0.37 / 0.77 |

On the clone, a standalone `CLUSTER` took 49 min, including the rebuild of all 8 indexes
(130 GB heap, 232 GB indexes). The vacuum after it took 2 min 54 s. During a sync, only 3 of
those indexes exist when the table is rewritten. On the steem-20 rebuild `20261125-9d02d5e7`,
the `CLUSTER` the sync used to run took 1,063 s; the parallel sort and copy-back replace it.
The tables stay LOGGED through massive sync, so the copy-back is WAL-logged; the sorted copy
is UNLOGGED.

Afterwards the table takes no extra disk space. While the rewrite runs, the sorted copy sits
beside the table until the transaction commits, and the truncated heap stays on disk until
then too. The parallel sort also spills to temporary files, roughly the size of the heap.
Expect a transient peak of about three times the heap size (about 390 GB on mainnet), plus
the rebuilt primary key and unique constraint.

## Existing nodes

The upgrade doesn't change an existing node. The node gets the order on its next rebuild
from scratch, or an operator can apply it by hand while hivemind is stopped (about 49 + 3
min on mainnet, under ACCESS EXCLUSIVE on `hive_votes`):

```sql
CLUSTER hivemind_app.hive_votes USING hive_votes_post_id_voter_id_idx;
VACUUM (FREEZE, ANALYZE) hivemind_app.hive_votes;
```

## Checking it

After a CI sync, `scripts/ci/check_votes_post_order.sql` asserts three things:

- The posts with 100 or more votes span at most 0.05 heap pages per vote.
- `pg_stats.correlation` of `hive_votes.post_id` is at least 0.99.
- At least 95% of the table's pages are all-visible.

On a live node, use the same queries. A node clustered by post has an `id` correlation well
below 1.0, so read the correlation of `post_id`, not `id`.
