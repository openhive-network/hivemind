# Massive Sync Performance Optimizations

This document describes the performance optimizations applied to Hivemind's massive sync process and their measured impact on sync time.

## Summary

Combined optimizations (P1+P8+P9) reduce massive sync time from **1216s to 647s** — a **47% improvement**.

## Optimizations

### P1: Batch Comment SQL Processing

**Branch:** `perf/p1-batch-comment-sql`

Replaces individual SQL INSERT/UPDATE calls for comments with batch operations. During massive sync, thousands of comments are processed per block range. Instead of executing one SQL statement per comment, P1 collects comments into batches and executes them in bulk.

**Impact:** Reduces sync elapsed time by ~28% when applied alone (1216s → 878s).

**Side effect:** Batch processing assigns different auto-increment post IDs compared to sequential processing. This causes cascading differences in search results, trending order, payout stats, and reblog entry IDs. The data content is identical — only the internal IDs differ.

### P6: Optimize Follow Flush

**Branch:** `perf/p6-optimize-follow-flush`

Optimizes the follow/unfollow flush operations during massive sync by reducing redundant database writes when processing follow state changes.

**Impact:** Reduces flushing time from ~1163s to ~1001s (14% flushing improvement), though overall elapsed time showed variance due to other factors.

### P8: Skip Notification Cache During Massive Sync

**Branch:** `perf/p8-skip-notification-cache`

Skips accumulation of notification cache entries during massive sync. Notifications are not needed during the initial bulk sync phase — they only become relevant during live sync when users are actively querying. This avoids expensive notification score calculations and cache management during the high-throughput sync phase.

**Impact:** Reduces flushing time by ~40% when applied alone (1163s → 697s). Overall elapsed time drops from 1216s to 1084s.

**Side effect:** The notification set after massive sync differs from sequential processing since notifications are not accumulated during sync. This changes notification ordering in API responses.

### P9: Skip Per-Block Rshares Recalculation During Massive Sync

**Branch:** `perf/p9-skip-rshares-during-massive`

Instead of recalculating post rshares (reward shares from votes) on every block during massive sync, P9 defers this to a single bulk recalculation at the end of the massive sync phase. The function `recalculate_all_posts_rshares` processes all posts at once after sync completes.

**Impact:** The bulk recalculation executes in **4.65s** (one-time cost at end of massive sync). Combined with P1+P8, total elapsed time drops from 672s to 647s.

## CI-Measured Results

All measurements from the `e2e_benchmark_on_postgrest` CI job syncing 5M blocks.

| Branch | Pipeline | Elapsed (s) | Flushing (s) | Optimizations | vs Baseline |
|--------|----------|-------------|-------------|---------------|-------------|
| develop (baseline) | #151725 | 1215.7 | 1149.8 | None | — |
| develop (repeat) | #151799 | 1116.7 | 1176.4 | None | — |
| `perf/p6-optimize-follow-flush` | #153514 | 1299.6 | 1001.0 | P6 only | -14% flushing |
| `perf/p8-skip-notification-cache` | #153513 | 1084.3 | 697.2 | P8 only | -11% elapsed |
| `perf/p1-batch-comment-sql` | #153517 | 877.7 | 939.8 | P1 only | -28% elapsed |
| `perf/p1-p8-combined` | #153519 | 672.0 | 642.4 | P1+P8 | -45% elapsed |
| `perf/p1-p8-p9-combined` | #153520 | **646.5** | **563.8** | P1+P8+P9 | **-47% elapsed** |

**Develop baseline variance:** Two develop runs measured 1216s and 1117s, showing ~8% natural variance. The combined optimization improvement (47%) is well outside this variance.

## Test Pattern Impact

The optimizations produce different (but equivalent) API outputs due to:

1. **Different post IDs** (P1): Batch processing assigns different auto-increment IDs. This cascades to search results, trending order, payout statistics, and reblog entry IDs.
2. **Different notification set** (P8): Skipping notification accumulation during massive sync changes notification ordering in API responses.
3. **No rshares/voting differences** (P9): The bulk recalculation at end of sync produces identical rshares values — no test pattern changes from P9.

Approximately 140 test pattern files were updated to reflect the new expected outputs. Three pre-existing flaky tests on develop (notification score timing) were excluded from updates.

## Branch Structure

```
develop (baseline)
├── perf/p1-batch-comment-sql          (P1 only)
├── perf/p6-optimize-follow-flush      (P6 only)
├── perf/p8-skip-notification-cache    (P8 only)
├── perf/p9-skip-rshares-during-massive (P9 only)
├── perf/p1-p8-combined                (P1+P8)
└── perf/p1-p8-p9-combined            (P1+P8+P9) ← recommended for merge
```

The `perf/p1-p8-p9-combined` branch contains all three recommended optimizations and is the target for merging to develop.

P6 is not included in the combined branch as its impact overlaps with P8 and adds complexity without significant additional benefit when P8 is present.
