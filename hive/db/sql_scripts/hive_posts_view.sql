CREATE OR REPLACE VIEW hivemind_app.live_posts_comments_view AS
SELECT
    hp.*,
    COALESCE(hpr.abs_rshares, 0) AS abs_rshares,
    COALESCE(hpr.vote_rshares, 0) AS vote_rshares,
    COALESCE(hpr.sc_hot, 0) AS sc_hot,
    COALESCE(hpr.sc_trend, 0) AS sc_trend,
    COALESCE(hpr.total_votes, 0) AS total_votes,
    COALESCE(hpr.net_votes, 0) AS net_votes
FROM hivemind_app.hive_posts hp
LEFT JOIN hivemind_app.hive_posts_rshares hpr ON hpr.post_id = hp.id
WHERE hp.counter_deleted = 0;

CREATE OR REPLACE VIEW hivemind_app.live_posts_view AS SELECT * FROM hivemind_app.live_posts_comments_view WHERE depth = 0;

CREATE OR REPLACE VIEW hivemind_app.live_comments_view AS SELECT * FROM hivemind_app.live_posts_comments_view WHERE depth != 0;

