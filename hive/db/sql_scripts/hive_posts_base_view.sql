DROP VIEW if exists public.hive_posts_base_view cascade;

CREATE OR REPLACE VIEW public.hive_posts_base_view
 AS
 SELECT 
    hp.block_num,
    hp.id,
    hp.author_id,
    hp.permlink_id,
    hp.payout,
    hp.pending_payout,
    COALESCE(( SELECT sum(
                CASE v.rshares >= 0
                    WHEN true THEN v.rshares
                    ELSE - v.rshares
                END) AS sum
           FROM hive_votes v
          WHERE v.post_id = hp.id AND NOT v.rshares = 0
          GROUP BY v.post_id), 0::numeric) AS abs_rshares
   FROM hive_posts hp
;
