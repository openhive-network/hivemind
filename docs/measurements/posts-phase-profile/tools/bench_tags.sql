-- aidev hivemind#472: cost of Step 5d's json_metadata parsing on the staging rows of the last batch (read-only)
\pset format unaligned
\pset tuples_only on
SELECT count(*) AS root_first_rows FROM hivemind_app._comment_staging cs JOIN hivemind_app._post_results pr ON pr.seq_id = cs.seq_id
 WHERE cs.is_first AND (cs.parent_author IS NULL OR cs.parent_author = '');
CREATE TEMP TABLE bench(variant text, ms float8);
DO $$
DECLARE i int; t0 timestamptz; n bigint;
BEGIN
  FOR i IN 1..7 LOOP
    -- A: as in process_posts_from_staging (subquery flattened, parse in every reference)
    t0 := clock_timestamp();
    SELECT count(*) INTO n FROM (
      SELECT pr.post_id, pr.is_new_post, cs.parent_permlink,
             hivemind_app.safe_parse_jsonb_tolerant(cs.op_body->>'json_metadata') AS parsed_md
      FROM hivemind_app._comment_staging cs JOIN hivemind_app._post_results pr ON pr.seq_id = cs.seq_id
      WHERE cs.is_first AND (cs.parent_author IS NULL OR cs.parent_author = '')) base,
    LATERAL (SELECT jsonb_array_elements_text(base.parsed_md->'tags') AS tag_val
             WHERE base.parsed_md IS NOT NULL AND base.parsed_md->'tags' IS NOT NULL AND jsonb_typeof(base.parsed_md->'tags') = 'array'
             UNION ALL SELECT base.parent_permlink) tags;
    INSERT INTO bench VALUES ('A current', extract(epoch FROM clock_timestamp() - t0) * 1000);
    -- B: subquery fenced with OFFSET 0, so the function runs once per row
    t0 := clock_timestamp();
    SELECT count(*) INTO n FROM (
      SELECT pr.post_id, pr.is_new_post, cs.parent_permlink,
             hivemind_app.safe_parse_jsonb_tolerant(cs.op_body->>'json_metadata') AS parsed_md
      FROM hivemind_app._comment_staging cs JOIN hivemind_app._post_results pr ON pr.seq_id = cs.seq_id
      WHERE cs.is_first AND (cs.parent_author IS NULL OR cs.parent_author = '') OFFSET 0) base,
    LATERAL (SELECT jsonb_array_elements_text(base.parsed_md->'tags') AS tag_val
             WHERE base.parsed_md IS NOT NULL AND base.parsed_md->'tags' IS NOT NULL AND jsonb_typeof(base.parsed_md->'tags') = 'array'
             UNION ALL SELECT base.parent_permlink) tags;
    INSERT INTO bench VALUES ('B parse once', extract(epoch FROM clock_timestamp() - t0) * 1000);
    -- C: parse once, validity checked with pg_input_is_valid instead of an EXCEPTION block (no subtransaction)
    t0 := clock_timestamp();
    SELECT count(*) INTO n FROM (
      SELECT post_id, is_new_post, parent_permlink, CASE WHEN pg_input_is_valid(md_text, 'jsonb') THEN md_text::jsonb END AS parsed_md
      FROM (SELECT pr.post_id, pr.is_new_post, cs.parent_permlink,
                   REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(cs.op_body->>'json_metadata', E'\b', '\b'), E'\f', '\f'), E'\n', '\n'), E'\r', '\r'), E'\t', '\t') AS md_text
            FROM hivemind_app._comment_staging cs JOIN hivemind_app._post_results pr ON pr.seq_id = cs.seq_id
            WHERE cs.is_first AND (cs.parent_author IS NULL OR cs.parent_author = '')) s OFFSET 0) base,
    LATERAL (SELECT jsonb_array_elements_text(base.parsed_md->'tags') AS tag_val
             WHERE base.parsed_md IS NOT NULL AND base.parsed_md->'tags' IS NOT NULL AND jsonb_typeof(base.parsed_md->'tags') = 'array'
             UNION ALL SELECT base.parent_permlink) tags;
    INSERT INTO bench VALUES ('C parse once, no subtransaction', extract(epoch FROM clock_timestamp() - t0) * 1000);
  END LOOP;
END $$;
SELECT variant, round(percentile_cont(0.5) WITHIN GROUP (ORDER BY ms)::numeric, 2) AS median_ms, round(min(ms)::numeric, 2) AS min_ms FROM bench GROUP BY 1 ORDER BY 1;
