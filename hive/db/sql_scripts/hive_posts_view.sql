CREATE OR REPLACE VIEW live_posts_comments_view AS SELECT * FROM hive_posts WHERE counter_deleted = 0 ;

CREATE OR REPLACE VIEW live_posts_view AS SELECT * FROM live_posts_comments_view WHERE depth = 0;

CREATE OR REPLACE VIEW live_comments_view AS SELECT * FROM live_posts_comments_view WHERE depth != 0;

