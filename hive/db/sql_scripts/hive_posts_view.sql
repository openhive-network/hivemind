CREATE OR REPLACE VIEW hivemind_app.live_posts_comments_view AS SELECT * FROM hivemind_app.hive_posts WHERE counter_deleted = 0 ;

CREATE OR REPLACE VIEW hivemind_app.live_posts_view AS SELECT * FROM hivemind_app.live_posts_comments_view WHERE depth = 0;

CREATE OR REPLACE VIEW hivemind_app.live_comments_view AS SELECT * FROM hivemind_app.live_posts_comments_view WHERE depth != 0;

