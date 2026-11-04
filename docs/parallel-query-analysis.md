# Parallel query in hivemind's API functions

Measured on 2026-11-03 against steem-20's full mainnet database (`haf-haf-1`,
`haf_block_log`, hivemind at block 111,318,595, PostgreSQL 18.6, 32 cores, 121 GiB),
with HAF frozen (`--skip-hived`) so both arms of every comparison read identical
data, and on the pinned mainnet shape `9381e39f59cb` for plan comparison.

## Answer

- Parallel query helps **none** of the 11 hot methods (94% of the pinned capture's
  calls). Every heavy statement they run is an index-driven lookup with no
  parallel-eligible scan. Marking every function the call graph allows
  `PARALLEL SAFE` changes no plan, on steem-20 or on the shape, and gains no
  latency or throughput (see the replay A/B below).
- The premise that a function's own `PARALLEL UNSAFE` marking keeps the queries
  inside it serial is wrong. A statement inside a PL/pgSQL or SQL function is
  planned on its own, and the only thing that matters is whether *it* calls
  something unsafe and how PL/pgSQL executes it (table below). The markings that
  matter are those of helpers called *inside* a query, not of the entry points.
- Exactly one API statement uses a parallel plan today, in the base build:
  `condenser_api_get_followers`' main query for heavily followed accounts (39
  workers over 6,215 executions in a full 15-minute replay of the capture). It is
  the case hivemind!460 worried about: an index-ordered plan over existing indexes
  is 17–113× faster serially for the common `limit 25` request.
- A blanket `PARALLEL SAFE` is not free: marking
  `hivemind_postgrest_utilities.apply_vote_presentation` safe makes
  `condenser_api.get_content_replies` 6–7% slower (424 ms against 400 ms for a
  518-reply thread, reproduced over three alternations) with no plan change,
  because `list_votes` re-plans its dynamic `EXECUTE` on every post and the
  planner then also builds partial paths over `hive_votes`.
- The server allows parallel plans: no setting change is needed or justified.

## Server settings in effect

`pg_settings` on the restarted steem-20 stack (`haf_api_node_perf-rebuild-20261026-17c8606f`,
HAF `b3c8655d`, hivemind `a751721d`); the non-default ones come from haf_api_node's
`pgtune.conf`.

| setting | value | source |
|---|---|---|
| `max_worker_processes` | 16 | pgtune.conf |
| `max_parallel_workers` | 16 | pgtune.conf |
| `max_parallel_workers_per_gather` | 4 | pgtune.conf |
| `max_parallel_maintenance_workers` | 4 | pgtune.conf |
| `parallel_setup_cost` / `parallel_tuple_cost` | 1000 / 0.1 | default |
| `min_parallel_table_scan_size` / `min_parallel_index_scan_size` | 8 MB / 512 kB | default |
| `parallel_leader_participation`, `enable_parallel_append`, `enable_parallel_hash` | on | default |
| `debug_parallel_query` | off | default |
| `max_parallel_apply_workers_per_subscription` | 2 | default |
| `random_page_cost` | 1.01 | pgtune.conf |
| `work_mem` / `shared_buffers` / `effective_cache_size` | 64 MB / 16 GB / 48 GB | pgtune.conf |
| `jit` | off | database setting |

These allow parallel plans (4 workers per Gather, 16 in total; pg_cron and the
logical replication launcher also take worker slots). `hivemind_user` sets only
`statement_timeout = 5000`. The parallel plans measured below did launch their
workers, so the settings were not what kept hivemind's API serial.

## How PostgreSQL decides, measured

Each case is a function marked `PARALLEL UNSAFE` (except where noted) running
`SELECT sum(length(name)) FROM hivemind_app.hive_accounts`, under `auto_explain`
(analyze) in a rolled-back transaction on steem-20:

| statement form | plan | workers launched | time |
|---|---|---|---|
| PL/pgSQL `RETURN QUERY` | Gather, Parallel Index Only Scan | 4 | 131 ms |
| PL/pgSQL `RETURN QUERY`, function marked `PARALLEL SAFE` | same | 4 | 142 ms |
| PL/pgSQL `RETURN QUERY`, called from a `DO` block (like `home`) | same | 4 | 137 ms |
| PL/pgSQL `SELECT … INTO` | Gather planned | **0** | 489 ms |
| PL/pgSQL assignment `x := (SELECT …)` | serial Index Only Scan | – | 222 ms |
| SQL-language function | Gather planned | **0** | 225 ms |

So the enclosing function's marking does not decide anything. What does:

- whether the statement itself calls a parallel-unsafe function (any one makes
  the whole statement serial), and
- how it runs: `RETURN QUERY` and a `RETURN (SELECT …)` expression can launch
  workers; `SELECT … INTO` and a non-inlined SQL function get a parallel plan
  but execute it in the leader alone, which is slower than the serial plan they
  would otherwise get (489 ms against 222 ms above). Most heavy hivemind
  statements are `SELECT … INTO` or `_result = (SELECT …)`.

## Parallel-safety audit

Every function reached from `hivemind_endpoints.home` and the 11 hot entry
functions (210 hivemind functions reachable from any `hivemind_endpoints` function; call graph read from `pg_proc.prosrc` and the views'
definitions) was checked for writes and DDL, temporary tables, cursors,
`set_config`/`SET`, parallel-unsafe or restricted built-ins, `SECURITY DEFINER`
and unsafe callees, transitively. A `SET` clause on a function is allowed in a
parallel worker (PostgreSQL saves and restores it), and so is a PL/pgSQL
exception block; neither blocks a marking.

- **155** hivemind functions could be marked `PARALLEL SAFE`, among them all the
  post view, post object, vote list, account and follow helpers the hot methods
  use.
- One of them first needs its volatility fixed:
  `hivemind_app.extract_img_url_from_json_metadata` is declared without a
  marking, so it is `VOLATILE PARALLEL UNSAFE`, though it only parses its
  argument. `get_post_view_by_id` and `get_full_post_view_by_id` call it, so it
  alone makes every statement that reads a post view parallel-unsafe. It is
  `IMMUTABLE`; marking it so (with `PARALLEL SAFE`) cost nothing measurable
  (397 ms against 396 ms on `get_content_replies`).
- **55** must stay unsafe, for five causes:
  - `hive.app_get_current_block_num` (HAF's, `PARALLEL UNSAFE`) through
    `hivemind_app.head_block_time` and `block_before_head`: the payout sorts of
    `get_ranked_posts`/`get_discussions_by_*`, the feed sort of
    `get_account_posts`, the notification methods and `list_pop_communities`;
  - `lite_posts.intercept` / `lite_social.intercept` (other applications' code,
    unsafe) through `hivemind_postgrest_utilities.dispatch` and everything that
    calls it (`rest_json_rpc_call`, `rest_json_rpc_rows`, the REST wrappers);
  - `set_config('response.headers', …)` in five REST endpoints
    (`get_version`, `get_sync_status`, `get_ops_by_account`,
    `get_account_pending_author_rewards`, `get_account_pending_curation_rewards`);
  - `hivemind_app.get_head_state` (`VOLATILE`), behind `hive.get_info` and
    `hive.db_head_state`;
  - `preprocess_search_query` (plpython3u, `SECURITY DEFINER`), behind
    `search-api.find_text`.
- Of the hot entry functions, `bridge_api_get_account_posts` and
  `bridge_api_get_ranked_posts` therefore stay unsafe (their feed and payout
  branches reach HAF); their posts/blog and trending/created branches, and the
  other nine hot entry functions, could be marked safe.

## Per hot method: plans and latency

The method's most frequent real arguments from the capture profile (as in
`performance.queries`), called through its `hivemind_endpoints` function on
steem-20, 12 calls per configuration in one session, the median of the last six
(the steady state a pooled PostgREST connection runs, after PL/pgSQL's plan cache
settles); every nested statement's plan captured with `auto_explain` (analyze,
buffers). *base*: today's markings. *candidate*: the 155 functions marked
`PARALLEL SAFE` and the image helper `IMMUTABLE PARALLEL SAFE`. *serial*: the same
with `max_parallel_workers_per_gather = 0`.

| method (calls/s in capture) | safe to mark? | heaviest statement's access path | base ms | base serial | candidate | candidate serial |
|---|---|---|---|---|---|---|
| bridge.get_discussion (40.9), 953-post thread | yes | recursive CTE on `hive_posts_parent_id_id_idx`, per-post `get_full_post_view_by_id` and `list_votes` index scans | 921.8 | 941.0 | 959.1 | 924.1 |
| bridge.get_post (31.5) | yes | `get_post_view_by_id` pkey lookups | 0.63 | 0.65 | 0.67 | 0.63 |
| bridge.get_profile (29.4) | yes | `hive_posts_author_id_*`, `hive_votes_voter_id_last_update_idx` index-only scans | 71.9 | 71.1 | 71.6 | 70.9 |
| condenser_api.get_follow_count (24.7) | yes | `hive_accounts_ux1`, pkey | 0.02 | 0.02 | 0.02 | 0.02 |
| condenser_api.get_content (16.1) | yes | `get_post_view_by_id`, `hive_votes_post_id_voter_id_idx` | 0.96 | 0.95 | 1.01 | 0.94 |
| bridge.get_account_posts sort=posts (10.1) | no (feed branch) | `hive_posts_author_id_id_depth0_idx` index-only | 0.16 | 0.16 | 0.15 | 0.15 |
| bridge.get_account_posts sort=blog | no (feed branch) | `hive_feed_cache_account_id_created_at_post_id_idx` index-only | 94.9 | 94.9 | 95.1 | 95.0 |
| bridge.get_community (7.9) | yes | `hive_communities_ux1`, pkey | 0.05 | 0.05 | 0.05 | 0.05 |
| condenser_api.get_followers (6.4), 18,072 followers, limit 1000 | yes | `follows_following_idx` + `hive_accounts_pkey` | 18.2 | 18.3 | 17.7 | 18.2 |
| condenser_api.get_following (6.3), 5,314 followed, limit 1000 | yes | `follows_pkey` index-only + `hive_accounts_pkey` | 5.54 | 5.61 | 5.49 | 5.54 |
| bridge.get_ranked_posts trending, tag "" (4.4) | no (payout branch) | `hive_posts_sc_trend_id_idx` | 85.7 | 85.6 | 85.6 | 86.0 |
| bridge.get_ranked_posts created, tag lassecash | no (payout branch) | `hive_post_tags_tag_id_post_id_idx` index-only | 28.7 | 28.6 | 29.0 | 28.7 |
| condenser_api.get_content_replies (3.2), 518 replies | yes | `hive_posts_parent_id_id_idx` index-only, per-reply `list_votes` | 396.3 | 396.4 | 423.9 | 395.4 |

No statement of any of these calls has a Gather node in any of the four
configurations: the plans with and without parallelism are the same plans, and
none scans a table sequentially. The differences are noise (±4% on
`get_discussion` across alternated sessions: 924–948 ms base, 941–946 ms
candidate) except `get_content_replies`, which is consistently 6–7% slower with
the candidate (397–401 ms base, 423–426 ms candidate, 397–403 ms candidate serial,
three alternations). Bisecting the 27 markings that call reaches isolated
`apply_vote_presentation`: alone it reproduces the slowdown (423 ms), and the 26
others together do not (396 ms). The slowdown persists under
`plan_cache_mode = force_generic_plan` (400 → 424 ms), so it is not the cached
plans: `list_votes` runs its query through `EXECUTE`, which is planned afresh on
each of the 518 posts, and with nothing unsafe left in it the planner also
considers parallel paths over `hive_votes` each time. A micro-benchmark of
20,000 cached point lookups shows no such cost (29 ms either way).

On the shape, `aidev db shape check` with the candidate installed plans every one
of the 15 declared queries the same as base: cost ratio 1.000, same plan, no
budget broken. Rerun on 2026-11-04 with the same 155 markings applied
on top of `25a3f0a` (base `25a3f0a`): identical costs on all 15 (from 9.75 for
`condenser-get-follow-count` to 268,604 for `condenser-get-content-replies` and
32,278 for `condenser-get-followers`), no plan diff, no new sequential scan.

## Where a parallel plan wins today: condenser_api.get_followers

`pg_stat_statements` (PostgreSQL 18 records `parallel_workers_launched`, and
`track = all` counts nested statements) over the base cold replay of the whole
capture (172,951 requests, 31.2 million statement executions by
`hivemind_user`): one statement launched workers, `condenser_api_get_followers`'
`RETURN COALESCE((SELECT jsonb_agg(…)))`, 39 workers over 6,215 executions. It
calls only built-ins, so it is parallel-eligible whatever its function's marking.

For an account with tens of thousands of followers the custom plan is a
4-worker Gather Merge: a parallel bitmap scan of every `follows` row of the
account, a `hive_accounts_pkey` lookup for each follower's name, a sort by name,
then the limit. `EXPLAIN (ANALYZE, BUFFERS)` on steem-20, warm, custom plans:

| account (followers) | limit | parallel (workers) | serial | index-ordered walk, serial |
|---|---|---|---|---|
| acidyo (33,162) | 25 | 66.5 ms (4), 163,648 buffers | 96.0 ms | **0.59 ms**, 734 buffers |
| acidyo | 1000 | 55.8 ms (4) | 77.2 ms | 72.1 ms (planner keeps the join) |
| appreciator (18,072) | 25 | 43.3 ms (3) | 39.4 ms | **2.56 ms**, 3,656 buffers |
| appreciator | 1000 | 37.1 ms (3) | 39.8 ms | 39.6 ms |
| blocktrades (30,987) | 25 | 57.2 ms (4) | 75.6 ms | **1.16 ms**, 1,766 buffers |
| blocktrades | 1000 | 54.9 ms (4) | 67.3 ms | 114.9 ms warm, 2,181 ms cold |

The walk is the query written so the planner can use what exists:
`hive_accounts_ux1 (name)` in order, probing `follows_pkey (follower, following)`
for each account (`WHERE ha.name > $start AND EXISTS (SELECT 1 FROM follows f
WHERE f.follower = ha.id AND f.following = $account) ORDER BY ha.name LIMIT $n`).
The current text's `(_start = '' OR ha.name > _start)` and the `UNION ALL` with
`muted` inside the limited CTE keep the planner from it. On the shape the walk
costs 1,432 against 46,963 for the current text (acidyo, limit 25).

- `limit 25` (54% of the capture's get_followers calls): the index-based plan
  beats the parallel one 17–113× serially. Recommendation: the rewrite, not
  `PARALLEL SAFE` (which this statement does not need anyway).
- `limit 1000` (45%): parallelism buys 1.2–1.4× for four extra processes, and no
  existing-index plan matches it. Forcing the walk is worse (blocktrades 115 ms
  warm). Hypothetical covering indexes `follows (following) INCLUDE (follower)`
  (~2.9 GiB) and `hive_accounts (id) INCLUDE (name)` (~94 MiB) cut the shape's
  cost 4× (47,102 → 11,539, still planned parallel; the shape tool cannot plan it
  with parallelism off). Not recommended at that size for 6.4 calls/s; leave the
  limit-1000 path as is.

### The walk as implemented

`condenser_api_get_followers` now decides per call, from `hive_accounts.followers`
(F) and `pg_class.reltuples` of `hive_accounts` (A, 2.62 million on steem-20).
Assuming followers spread evenly over names, a page of L takes about L·A/F probes.
It walks when 2·L·A/F < F and gives up after 2·L·A/F accounts, falling back to
today's query when the page is not full. The walk runs as a PL/pgSQL `FOR` loop,
whose query is planned without parallelism. Left to itself, the planner puts the
walk under a 4-worker Gather Merge on steem-20 and on the shape, and every worker
then walks until it alone has 25 rows: acidyo limit 25 took 175 ms cold that way.

`EXPLAIN (ANALYZE, BUFFERS)` on steem-20, 2026-11-04, today's query against the
bounded serial walk, two runs each. Today's first runs were cold (acidyo 25: 192 ms,
cryptoriddler 25: 501 ms). The walk's runs came after other walks had warmed part of
`hive_accounts_ux1`.

| account (followers) | limit | today, second run | walk, first / second run | accounts walked (budget) |
|---|---|---|---|---|
| acidyo (33,164) | 25 | 49.0 ms | 1.40 / 0.16 ms, 739 buffers | 144 (3,954) |
| acidyo | 100 | 48.3 ms | 15.8 / 6.9 ms | 4,134 (15,814) |
| appreciator (18,072) | 25 | 31.9 ms | 1.06 / 0.79 ms | 736 (7,256) |
| blocktrades (30,987) | 25 | 49.0 ms | 0.43 / 0.38 ms | 351 (4,232) |
| blocktrades | 100 | 45.7 ms | 8.3 / 6.0 ms | 5,312 (16,925) |
| cryptoriddler (101,888) | 25 | 142.0 ms | 0.19 / 0.13 ms | 118 (1,287) |
| cryptoriddler | 1000 | 135.2 ms | 32.9 / 19.4 ms | 15,670 (51,474) |
| dtube (89,695) | 1000 | 139.3 ms | 38.7 / 35.3 ms | 26,199 (58,471) |
| ptthuy888 (50,506) | 25 | 21.1 ms | 2.97 / 2.41 ms, finds 3, falls back | 2,596 (2,596) |
| ptthuy888 | 100 | 22.0 ms | 12.2 / 11.0 ms, finds 4, falls back | 10,384 (10,384) |

Every page that filled used under 0.45 of its budget. At limit 1000, acidyo,
appreciator and blocktrades stay on today's plan (their 2·L·A/F exceeds F).
Unbounded, the walk would cost them 73.6, 42.8 and 67.3 ms warm. The bound is
there for accounts whose followers cluster in one name range. Unbounded,
ptthuy888's limit-25 walk took 136 ms warm and 927 ms cold, against today's 21 ms.
Bounded, the wasted walk costs it 2.4 ms (limit 25) or 11 ms (limit 100) before
the fallback. On the shape, the nested call for acidyo limit 25 costs 71 in total
(the walk 58.6), and for appreciator 111 against 32,133. At limit 1000 it keeps
today's plan (47,120 for acidyo), and the declared `condenser-get-followers` query
compares at ratio 1.000.

## Under load: replay A/B

`aidev replay ab --base a751721d --candidate 2f1f2805 --capacity 2x,5x
--max-seconds 450` on steem-20, 2026-11-04 00:17–01:44 UTC, over the first 450 s of
the pinned capture `8d7e6cb73d08`: 87,057 requests per run, chain frozen
(`--skip-hived`), each build cold (shared buffers evicted) then warm, then warm
at 2× and 5× the captured rate. `a751721d` is the build steem-20 runs. The
candidate `2f1f2805` is that build plus one script at the end of `load_order.sql`
that marks the audit's 155 functions `PARALLEL SAFE` and the image helper
`IMMUTABLE`. Every install reloads all runtime SQL, so the markings are the only
difference. Between the runs, `pg_proc` showed 155 safe functions under the
candidate and 1 under base. The candidate never lands.

Two things on the node had to change before the build switch did anything:
- `compose.rebuild-pins.yml` pins the hivemind images by digest. A first
  attempt therefore ran the base for both arms. Its base-against-base legs are
  the noise floor quoted below.
- `hivemind-install` skips its install while `hivemind-block-processing` holds
  the install lock.

For the run, the three hivemind pins read `${HIVEMIND_VERSION}` and
block-processing was stopped (with HAF frozen it has nothing to index). Both
are back as they were, and hivemind has caught up to the head.

The tool's verdict is `invalid` because the base answers 4.8% of requests with
an error, over the profile's 1% budget. Those errors are the capture's own bad
requests (posts that do not exist, wrong parameters), answered identically by
both builds (4,262 against 4,268 cold, 4,269 against 4,266 warm), with 0
response differences. They do not affect the latency comparison.

Whole run (all methods, ms; timeouts are over 5 s):

| run | rate achieved | p50 | p95 | p99 | timeout rate |
|---|---:|---:|---:|---:|---:|
| base cold | 175.8 req/s | 3.2 | 32.3 | 110.7 | 0.0006 |
| candidate cold | 175.8 req/s | 3.0 | 30.4 | 106.3 | 0.0005 |
| base warm | 175.8 req/s | 2.9 | 29.7 | 105.1 | 0.0007 |
| candidate warm | 175.8 req/s | 2.8 | 28.4 | 102.3 | 0.0006 |
| base 2× | 324.4 req/s | 2.9 | 30.3 | 106.1 | 0.0008 |
| candidate 2× | 324.6 req/s | 2.9 | 30.0 | 107.6 | 0.0007 |
| base 5× | 670.9 req/s | 3.7 | 32.6 | 115.6 | 0.0012 |
| candidate 5× | 671.3 req/s | 4.0 | 35.2 | 120.1 | 0.0009 |

Hot methods, p95 / p99 in ms, base → candidate:

| method | cold | warm | 2× | 5× |
|---|---|---|---|---|
| bridge.get_discussion | 32.8/124.9 → 30.8/120.7 | 30.5/120.6 → 29.2/116.2 | 30.8/123.2 → 31.0/124.6 | 32.6/131.4 → **35.9/143.1** |
| bridge.get_post | 10.2/16.5 → 9.3/14.5 | 9.2/14.1 → 8.8/13.3 | 9.2/14.3 → 9.1/14.2 | 10.7/16.6 → 11.6/18.0 |
| bridge.get_profile | 19.5/102.1 → 18.9/104.3 | 18.6/85.3 → 18.1/81.8 | 18.7/87.1 → 18.8/85.4 | 20.8/98.0 → 21.4/98.4 |
| condenser_api.get_follow_count | 1.1/1.4 → 1.0/1.2 | 1.1/1.4 → 1.0/1.2 | 1.0/1.2 → 1.0/1.2 | 3.3/5.5 → 3.4/5.9 |
| condenser_api.get_content | 10.1/18.5 → 9.4/16.8 | 9.4/16.3 → 9.0/16.1 | 9.4/17.0 → 9.4/17.5 | 11.5/19.4 → 12.1/21.1 |
| bridge.get_account_posts | 142.3/244.6 → 129.4/227.9 | 130.2/217.9 → 123.9/201.0 | 133.7/218.7 → 131.2/222.5 | 138.9/235.2 → **148.9/247.8** |
| bridge.get_community | 1.3/1.8 → 1.2/1.5 | 1.2/1.5 → 1.2/1.4 | 1.2/1.6 → 1.2/1.6 | 3.9/6.8 → 4.0/6.2 |
| condenser_api.get_followers | 38.9/90.6 → 37.2/81.6 | 34.2/84.8 → 33.4/80.3 | 36.1/86.6 → 34.8/87.0 | 40.6/105.4 → 42.3/108.1 |
| condenser_api.get_following | 4.6/12.9 → 4.4/12.4 | 4.3/12.7 → 4.5/11.8 | 4.3/12.8 → 4.4/13.2 | 6.4/14.5 → 7.0/14.9 |
| bridge.get_ranked_posts | 90.9/117.5 → 86.3/106.7 | 87.1/105.1 → 83.8/102.3 | 87.5/103.1 → 86.6/108.2 | 92.6/122.0 → **99.1/126.0** |
| condenser_api.get_content_replies | **211.8/443.5 → 225.9/470.0** | **205.5/442.4 → 224.0/456.4** | **217.7/444.8 → 229.2/467.8** | **227.8/485.6 → 243.4/515.5** |

What this shows:
- **Throughput:** no difference. The replay paces requests at the offered rate, and
  both builds kept up at 5× (671 req/s, p95 well under the 2 s budget). Neither
  build saturated, so the run found no throughput ceiling for either.
- **Single-rate latency:** the candidate is 2–9% faster at p95 on most methods
  cold and warm. That is inside the noise floor: in the first attempt, the base
  against itself moved the whole-run cold p95 by 14% (35.0 → 30.1 ms), with 17
  "unexpected" differences and 12 flagged "regressions" between identical builds.
  The plans are identical, so there is nothing for the candidate to win with.
- **Flagged, worse with the candidate:**
  - `condenser_api.get_content_replies` is slower at every rate (p95 +7% cold,
    +9% warm, +5% at 2×, +7% at 5×; p99 +3% to +6%). This is the
    `apply_vote_presentation` re-planning cost bisected above. It is the one
    consistent tail regression.
  - At 5× the candidate's p95 is 3–10% higher on most hot methods
    (`get_discussion` +10% p95 / +9% p99, `get_ranked_posts` +7%,
    `get_account_posts` +7%), and the whole-run p95 is 32.6 → 35.2 ms. It is one
    run per build, the candidate's ran second under a higher host load (load1
    mean 3.9 against 3.5), and it hits methods whose plans did not change. So it
    is not attributable to parallel workers, but it is a tail cost under load
    with no gain anywhere to set against it.
- The timeout counts (5 s) are spread over trivial methods (`get_follow_count`,
  `get_community`) in both builds, at 0.05–0.12% of requests. They are node
  stalls, not query plans.

The tool's own report (`replay-report.json` and the full text output) is kept with
the workflow's artifacts. The driver ran from session24 (134 ms RTT to
steem-20). goreplay measures latency on steem-20 itself, so the link affects
only progress reporting.

## Recommendations

Per function, each backed by a number above. The follow-up implementation
issue, #437, carries the same list.

| function | decision | number it rests on |
|---|---|---|
| `hivemind_endpoints.condenser_api_get_followers` | **rewrite the main query** as the index-ordered walk over `hive_accounts_ux1` probing `follows_pkey` (plain `ha.name > _start`, the `muted` branch kept out of the limited walk), at least for small limits; keep today's plan for large ones | limit 25: 0.59–2.56 ms serial against 43–67 ms parallel (17–113×); limit 1000: the walk is 1.07–2.1× slower than the parallel plan (39.6–114.9 ms against 37.1–55.8 ms), so it must not replace the parallel plan there |
| `hivemind_app.extract_img_url_from_json_metadata` | **declare `IMMUTABLE PARALLEL SAFE`** (it is `VOLATILE PARALLEL UNSAFE` only because it has no marking); a correctness fix, not a speed-up | 397 ms against 396 ms on `get_content_replies`; it is the one marking that makes every post-view statement parallel-unsafe |
| `hivemind_postgrest_utilities.apply_vote_presentation` | **leave as is** (unsafe) | marking it safe makes `get_content_replies` 6–7% slower (423–426 ms against 397–401 ms) with no plan change |
| the other 153 functions the audit allows, among them the hot entry functions `bridge_api_get_discussion`, `bridge_api_get_post`, `bridge_api_get_profile`, `condenser_api_get_follow_count`, `condenser_api_get_content`, `bridge_api_get_community`, `condenser_api_get_following`, `condenser_api_get_content_replies` | **leave as is** | no plan changes on steem-20 or on the shape (cost ratio 1.000 on all 15 declared queries), per-call medians within ±4%, and the replay A/B above shows no gain |
| `bridge_api_get_account_posts`, `bridge_api_get_ranked_posts`, and the other 53 unsafe functions | **leave as is**: they cannot be marked (HAF's `hive.app_get_current_block_num`, the lite intercepts, `set_config`, `get_head_state`, plpython) | audit above |
| server settings (`max_parallel_workers_per_gather = 4`, `max_parallel_workers = 16`, `max_worker_processes = 16`) | **no change** | they allow parallel plans (the measured `get_followers` plans launched 3–4 workers); nothing in the API read path is held back by them |

What would make a later re-check worthwhile: a hot method whose plan gains a
large sequential or bitmap scan (the shape check's 1 GiB Seq Scan budget flags
it), or a change that moves a heavy statement from `SELECT … INTO` to
`RETURN QUERY`, the one form that both plans and runs in parallel.

## Not analysed

- The methods outside the hot set (6% of the capture's calls, about 11
  calls/s) were audited for safety but not timed one by one; the replay covers them in aggregate and `pg_stat_statements` shows none
  of them launching workers.
- Cold single calls: the per-call table is warm. The replay's cold runs evict
  PostgreSQL's shared buffers only (a PostgreSQL restart), not the OS page cache
  or ZFS ARC.
- The value catalog: the pinned shape holds none, so the shape plans each
  declared query at its one declared value; the steem-20 measurements use the
  heavy values (heaviest thread, most followed accounts) instead.
- Methods that only marking HAF's `hive.app_get_current_block_num` or the lite
  applications' intercepts safe would open; those are other projects' code.
