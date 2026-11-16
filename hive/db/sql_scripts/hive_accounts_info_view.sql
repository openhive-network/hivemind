DROP VIEW IF EXISTS hivemind_app.hive_accounts_info_view_lite CASCADE;
CREATE OR REPLACE VIEW hivemind_app.hive_accounts_info_view_lite
 AS
 SELECT ha.id,
    ha.name,
    ha.post_count::bigint AS post_count,
    ha.created_at,
    ha.reputation,
    ha.rank,
    ha.following,
    ha.followers,
    ha.lastread_at,
    ha.posting_json_metadata,
    ha.json_metadata
   FROM hivemind_app.hive_accounts_view ha
   ;

DROP VIEW IF EXISTS hivemind_app.hive_accounts_info_view;
CREATE OR REPLACE VIEW hivemind_app.hive_accounts_info_view
 AS
 SELECT ha.id,
    ha.name,
    ha.post_count,
    ha.created_at,
    GREATEST(ha.created_at,
             COALESCE(latest_post.latest_post_time, '1970-01-01 00:00:00'::timestamp without time zone),
             COALESCE(whole_votes.latest_vote_time, '1970-01-01 00:00:00'::timestamp without time zone)) AS active_at,
    ha.reputation,
    ha.rank,
    ha.following,
    ha.followers,
    ha.lastread_at,
    ha.posting_json_metadata,
    ha.json_metadata
   FROM hivemind_app.hive_accounts_info_view_lite ha
   LEFT JOIN LATERAL 
   (
      SELECT MAX(hp1.created_at) AS latest_post_time
      FROM hivemind_app.hive_posts hp1                     -- hive_posts_author_id_created_at_id_idx
      WHERE hp1.author_id = ha.id
   ) latest_post on true
   LEFT JOIN LATERAL
   (
     SELECT MAX(hvf.last_update) AS latest_vote_time
     FROM hivemind_app.hive_votes hvf                      
     WHERE hvf.voter_id = ha.id                         -- hive_votes_voter_id_last_update_idx
   ) whole_votes ON true
   ;
