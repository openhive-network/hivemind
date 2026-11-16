-- After a massive sync from scratch, checks that hive_votes is stored in post order and vacuumed:
--   - the posts with at least 100 votes span at most 0.05 heap pages per vote, together;
--   - pg_stats.correlation of hive_votes.post_id is at least 0.99;
--   - at least 95% of hive_votes' pages are all-visible.
-- Votes written after the rewrite (the blocks a sync processes once its indexes are
-- restored) are appended in block order, which these bounds leave room for.
--   psql -X -v ON_ERROR_STOP=1 -f scripts/ci/check_votes_post_order.sql
\set QUIET on

DO $$
DECLARE
    __pages_per_vote FLOAT;
    __posts BIGINT;
    __correlation FLOAT;
    __all_visible FLOAT;
BEGIN
    SELECT sum(pages)::FLOAT / sum(votes), count(*)
    INTO __pages_per_vote, __posts
    FROM (
        SELECT count(DISTINCT (ctid::TEXT::POINT)[0]) AS pages, count(*) AS votes
        FROM hivemind_app.hive_votes
        GROUP BY post_id
        HAVING count(*) >= 100
    ) p;

    SELECT correlation INTO __correlation
    FROM pg_stats
    WHERE schemaname = 'hivemind_app' AND tablename = 'hive_votes' AND attname = 'post_id';

    SELECT relallvisible::FLOAT / nullif(relpages, 0) INTO __all_visible
    FROM pg_class
    WHERE oid = 'hivemind_app.hive_votes'::regclass;

    RAISE NOTICE 'hive_votes: % heap pages per vote over % posts with 100+ votes, post_id correlation %, % all-visible',
        round(__pages_per_vote::NUMERIC, 4), __posts, round(__correlation::NUMERIC, 4), round(__all_visible::NUMERIC, 4);

    ASSERT __posts > 0, 'no post has 100 votes, so the check measures nothing';
    ASSERT __pages_per_vote <= 0.05, format('hive_votes is not in post order: %s heap pages per vote', __pages_per_vote);
    ASSERT __correlation >= 0.99, format('hive_votes.post_id correlation is %s', __correlation);
    ASSERT __all_visible >= 0.95, format('only %s of hive_votes'' pages are all-visible', __all_visible);
END
$$;
