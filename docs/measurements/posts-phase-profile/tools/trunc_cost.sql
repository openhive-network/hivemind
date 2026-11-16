-- aidev hivemind#472: what one TRUNCATE of a small staging table costs, against DELETE (shared_buffers as configured)
\pset format unaligned
SHOW shared_buffers;
DROP TABLE IF EXISTS public.aidev472_tc;
CREATE UNLOGGED TABLE public.aidev472_tc (LIKE hivemind_app._post_batch);
CREATE INDEX ON public.aidev472_tc (author_id, permlink_id);
CREATE TEMP TABLE tc_bench(variant text, ms float8);
DO $$
DECLARE i int; t0 timestamptz;
BEGIN
  FOR i IN 1..200 LOOP
    INSERT INTO public.aidev472_tc (seq_id, author_id, permlink_id) SELECT g, g, g FROM generate_series(1, 300) g;
    t0 := clock_timestamp();
    TRUNCATE public.aidev472_tc;
    INSERT INTO tc_bench VALUES ('truncate', extract(epoch FROM clock_timestamp() - t0) * 1000);
    INSERT INTO public.aidev472_tc (seq_id, author_id, permlink_id) SELECT g, g, g FROM generate_series(1, 300) g;
    t0 := clock_timestamp();
    DELETE FROM public.aidev472_tc;
    INSERT INTO tc_bench VALUES ('delete', extract(epoch FROM clock_timestamp() - t0) * 1000);
  END LOOP;
END $$;
SELECT variant, count(*), round(percentile_cont(0.5) WITHIN GROUP (ORDER BY ms)::numeric, 3) AS median_ms, round(avg(ms)::numeric, 3) AS mean_ms FROM tc_bench GROUP BY 1 ORDER BY 1;
DROP TABLE public.aidev472_tc;
