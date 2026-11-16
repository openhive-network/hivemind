# Steps 5d/5e: parse each root post's `json_metadata` once

`process_posts_from_staging` (`hive/db/sql_scripts/massive_sync.sql`) reads each root post's tags from
`safe_parse_jsonb_tolerant(op_body->>'json_metadata')` in a subquery `base` that the `LATERAL` after it references
four times. The planner flattened `base` and ran the function (PL/pgSQL with an `EXCEPTION` block, so a
subtransaction per call) in every reference. `OFFSET 0` now fences `base` in both steps.

## 19.0–19.5M sample (steem-19 clone `haf-pool/aidev472@s19`, 2026-11-16)

Two runs of #472's `tools/run_sample.sh` (LOGGED, 500 batches, blocks 19,001,001–19,500,000, image
`aidev472/hivemind:ba5c5943`) with `track_functions = pl`. A ran the image's `massive_sync.sql`, and B ran the same
file with only the two `OFFSET 0` lines added (bind-mounted).

| | A (as before) | B (fenced) | change |
|---|---|---|---|
| Step 5d, exclusive s (`tags_5d`) | 45.4 | 35.4 | −22 % |
| Step 5e, exclusive s (`tags_5e`) | 10.9 | 8.9 | −18 % |
| Steps 5d + 5e, ms/batch | 112.7 | 88.6 | −21 % |
| `safe_parse_jsonb_tolerant` calls, all callers | 47,992,561 | 44,234,733 | −3,757,828 |
| `safe_parse_jsonb_tolerant` self time, all callers | 54.7 s | 45.6 s | −9.1 s |
| `hive_post_tags` rows / sum of `hashtextextended(post_id:tag)` | 24,422,621 / −18633401405979702553265 | the same | identical |

The posts phase as a whole was 856 s in A and 675 s in B. Most of that difference is run-to-run noise outside
Steps 5d/5e: `hp_ins_comments` went from 386 to 314 s and `cs_norm` from 64.8 to 6.8 s, neither touched by the
change. So the tags-step reduction may also be partly noise. The function's self time (−9.1 s, about 18 ms per
batch) bounds what parsing once saves. The 30 % target for Steps 5d + 5e is not reached: what remains of them is
not the parsing.

## Call counts (synthetic, PostgreSQL 17)

On 1,007 root posts with distinct metadata and 202 edited root posts in `_comment_staging`, Step 5d + 5e's
`SELECT`s call the function 4,824 times as before and 1,209 times (posts + edited posts) when fenced, returning
identical rows. The cases covered are well-formed tags, `tags` a string, `tags` null, no `tags`, malformed JSON,
double-encoded (string) metadata, metadata containing control characters, and edits replacing tags.
