DROP VIEW IF EXISTS hive_accounts_info_view;
CREATE OR REPLACE VIEW public.hive_accounts_info_view
 AS
 SELECT ha.id,
    ha.name,
    COALESCE(post_data.post_count, 0::bigint) AS post_count,
    ha.created_at,
    ( SELECT GREATEST(ha.created_at,
                      COALESCE(post_data.latest_post, '1970-01-01 00:00:00'::timestamp without time zone),
                      COALESCE(limited_votes.latest_vote, whole_votes.latest_vote, '1970-01-01 00:00:00'::timestamp without time zone))
                      AS "greatest"
                     ) AS active_at,
    ha.reputation,
    ha.rank,
    ha.following,
    ha.followers,
    ha.lastread_at,
    ha.posting_json_metadata,
    ha.json_metadata,
    ha.blacklist_description,
    ha.muted_list_description
   FROM
   (
   SELECT max(hb.num) - 1200 * 24 * 7 AS block_limit FROM hive_blocks hb
   ) bl,
   hive_accounts ha
   LEFT JOIN LATERAL
   ( 
     SELECT count(1) AS post_count, max(hp.created_at) AS latest_post, max(hp.block_num) AS latest_post_block
     FROM hive_posts hp
     WHERE hp.author_id = ha.id
   ) post_data ON true
   LEFT JOIN LATERAL --- let's first try to find a last vote in last 7 days
   (
     SELECT hv.last_update AS latest_vote
     FROM hive_votes hv
     WHERE ha.id = hv.voter_id AND hv.block_num >= bl.block_limit AND hv.block_num >= COALESCE(post_data.latest_post_block, 0)
     ORDER BY hv.block_num DESC
     LIMIT 1
   ) limited_votes ON true
   LEFT JOIN LATERAL -- this is a fallback to case when was no vote in last 7 days
   (
     SELECT hvf.last_update AS latest_vote
     FROM hive_votes hvf
     WHERE limited_votes.latest_vote IS NULL AND hvf.voter_id = ha.id
     ORDER BY hvf.voter_id DESC, hvf.last_update DESC
     LIMIT 1
   ) whole_votes ON true
   ;


