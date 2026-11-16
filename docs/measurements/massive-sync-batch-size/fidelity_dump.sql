-- Natural-key dumps of the synced data (ids are drawn in processing order, so they are replaced by natural keys)
CREATE TEMP TABLE pk AS
SELECT hp.id, ha.name || '/' || hpd.permlink || '#' || hp.counter_deleted AS k
FROM hivemind_app.hive_posts hp
JOIN hivemind_app.hive_accounts ha ON ha.id = hp.author_id
JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id;
CREATE INDEX ON pk (id);
ANALYZE pk;

\o posts.txt
SELECT pk.k, ppk.k AS parent, rpk.k AS root,
       (to_jsonb(hp) - 'id' - 'parent_id' - 'root_id')::text
FROM hivemind_app.hive_posts hp
JOIN pk ON pk.id = hp.id
LEFT JOIN pk ppk ON ppk.id = hp.parent_id
LEFT JOIN pk rpk ON rpk.id = hp.root_id
ORDER BY 1;

\o votes.txt
SELECT v.name || '>' || hpd.permlink || '@' || a.name AS k, pk.k AS post,
       (to_jsonb(hv) - 'id' - 'post_id')::text
FROM hivemind_app.hive_votes hv
JOIN hivemind_app.hive_accounts v ON v.id = hv.voter_id
JOIN hivemind_app.hive_accounts a ON a.id = hv.author_id
JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hv.permlink_id
LEFT JOIN pk ON pk.id = hv.post_id
ORDER BY 1;

\o notifs.txt
SELECT n.type_id, n.block_num, n.src, n.dst, pk.k AS post, dpk.k AS dst_post,
       (to_jsonb(n) - 'id' - 'post_id' - 'dst_post_id')::text
FROM hivemind_app.hive_notification_cache n
LEFT JOIN pk ON pk.id = n.post_id
LEFT JOIN pk dpk ON dpk.id = n.dst_post_id
ORDER BY 1, 2, 3, 4, 5, 6, 7;

\o mentions.txt
SELECT pk.k, m.account_id, m.block_num
FROM hivemind_app.hive_mentions m LEFT JOIN pk ON pk.id = m.post_id
ORDER BY 1, 2, 3;

\o postdata.txt
SELECT pk.k, md5(coalesce(d.title, '')), md5(coalesce(d.body, '')), md5(coalesce(d.json, ''))
FROM hivemind_app.hive_post_data d LEFT JOIN pk ON pk.id = d.id
ORDER BY 1;

\o counts.txt
SELECT 'posts', count(*) FROM hivemind_app.hive_posts
UNION ALL SELECT 'deleted_posts', count(*) FROM hivemind_app.hive_posts WHERE counter_deleted > 0
UNION ALL SELECT 'votes', count(*) FROM hivemind_app.hive_votes
UNION ALL SELECT 'votes_on_deleted', count(*) FROM hivemind_app.hive_votes hv JOIN hivemind_app.hive_posts hp ON hp.id = hv.post_id WHERE hp.counter_deleted > 0
UNION ALL SELECT 'sum_num_changes', sum(num_changes) FROM hivemind_app.hive_votes
UNION ALL SELECT 'notifs', count(*) FROM hivemind_app.hive_notification_cache
UNION ALL SELECT 'mention_notifs', count(*) FROM hivemind_app.hive_notification_cache WHERE type_id = 16
UNION ALL SELECT 'mentions', count(*) FROM hivemind_app.hive_mentions
UNION ALL SELECT 'post_data', count(*) FROM hivemind_app.hive_post_data
UNION ALL SELECT 'last_completed', last_completed_block_num FROM hivemind_app.hive_state;
\o
