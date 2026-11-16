# hive_votes in post order

Massive sync writes votes in block order. A post collects its votes over about a week,
mixed in with every other vote of that week, so they end up about 0.67 heap pages apart.
Reading a post's votes (`top_votes`, `observer_vote`, `active_votes`) then reads about one
heap page per vote. That made `hive_votes` the table with the most physical reads on
api.syncad.com.

## What a sync from scratch does

When an initial sync first restores its registered indexes, the `hive_votes` restore thread
does three things before it restores that table's other indexes
(`DbState._order_hive_votes_by_post`):

1. It builds `hive_votes_post_id_voter_id_idx` from its registered command, which is
   `CREATE INDEX IF NOT EXISTS`.
2. It runs `CLUSTER hivemind_app.hive_votes USING hive_votes_post_id_voter_id_idx`. This
   rewrites the heap in `(post_id, voter_id)` order and rebuilds the indexes massive sync
   kept: the primary key, the `(voter_id, author_id, permlink_id)` unique constraint, and
   the index from step 1. The other registered indexes are still dropped at this point.
3. It runs `VACUUM (FREEZE, ANALYZE)` on the table, to set the visibility map and collect
   statistics.

The restore that follows skips the index from step 1, because it already exists. The other
tables restore their indexes in parallel threads, so they don't wait for this step.

The sync log reports the step's added time:

```
[MASSIVE] Ordered hivemind_app.hive_votes by post_id in <s> (index build <s>, CLUSTER <s>, VACUUM <s>); <n> of <m> pages all-visible
```

If the vacuum cannot mark the pages all-visible (another app's snapshot is older than the
rows, #459), the VisibilityWatch of live sync vacuums the table again later.

If the process stops after `CLUSTER` commits, `pg_index.indisclustered` shows that the
rewrite is done, and the next start skips it. The step runs only during an initial sync
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
those indexes exist when `CLUSTER` runs. The tables stay LOGGED through massive sync, so the
rewrite is WAL-logged.

Afterwards the table takes no extra disk space. While `CLUSTER` runs, the old heap stays in
place until the command commits. The sort also spills to temporary files, roughly the size
of the heap. Expect a transient peak of about twice the heap size (about 260 GB on mainnet),
plus the rebuilt primary key and unique constraint.

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
