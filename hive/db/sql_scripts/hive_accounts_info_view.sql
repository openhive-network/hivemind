DROP VIEW IF EXISTS hivemind_app.hive_accounts_info_view_lite CASCADE;
CREATE OR REPLACE VIEW hivemind_app.hive_accounts_info_view_lite
 AS
 SELECT ha.id,
    ha.name,
    COALESCE(posts.post_count, 0::bigint) AS post_count,
    ha.created_at,
    ha.reputation,
    ha.rank,
    ha.following,
    ha.followers,
    ha.lastread_at,
    ha.posting_json_metadata,
    ha.json_metadata
   FROM hivemind_app.hive_accounts ha
   LEFT JOIN LATERAL
   ( 
     SELECT COUNT(1) AS post_count
     FROM hivemind_app.hive_posts hp
     WHERE hp.counter_deleted = 0 and hp.author_id = ha.id
   ) posts ON true
   ;

DROP VIEW IF EXISTS hivemind_app.hive_accounts_info_view;
CREATE OR REPLACE VIEW hivemind_app.hive_accounts_info_view
 AS
 SELECT ha.id,
    ha.name,
    ha.post_count,
    ha.created_at,
    ( SELECT GREATEST(ha.created_at,
                      COALESCE(latest_post.latest_post, '1970-01-01 00:00:00'::timestamp without time zone),
                      COALESCE(whole_votes.latest_vote, '1970-01-01 00:00:00'::timestamp without time zone))
                      AS "greatest"
                     ) AS active_at,
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
      SELECT hp1.created_at AS latest_post
      FROM hivemind_app.hive_posts hp1
      WHERE hp1.counter_deleted = 0 and hp1.author_id = ha.id
      ORDER BY hp1.created_at DESC, hp1.author_id DESC LIMIT 1
   ) latest_post on true
   LEFT JOIN LATERAL
   (
     SELECT hvf.last_update AS latest_vote
     FROM hivemind_app.hive_votes hvf
     WHERE hvf.voter_id = ha.id
     ORDER BY hvf.voter_id DESC, hvf.last_update DESC LIMIT 1
   ) whole_votes ON true
   ;
