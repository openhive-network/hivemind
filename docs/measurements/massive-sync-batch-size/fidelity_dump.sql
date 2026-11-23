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

-- Ids as drawn (#482): posts with their parent and root, notifications whole
\o post_ids.txt
SELECT hp.id, pk.k, hp.parent_id, hp.root_id
FROM hivemind_app.hive_posts hp
JOIN pk ON pk.id = hp.id
ORDER BY 1;

\o notif_ids.txt
SELECT n.id, n.type_id, n.block_num, n.src, n.dst, n.post_id, n.dst_post_id, n.score, n.payload
FROM hivemind_app.hive_notification_cache n
ORDER BY 1;

-- Accounts by name, every column (ids are HAF's account ids, the same in every run)
\o accounts.txt
SELECT ha.name, to_jsonb(ha)::text
FROM hivemind_app.hive_accounts ha
ORDER BY 1;

-- The follow and mute lists on natural keys
\o follows.txt
SELECT fr.name, fo.name, l.block_num, l.follower_name
FROM hivemind_app.follows l
JOIN hivemind_app.hive_accounts fr ON fr.id = l.follower
JOIN hivemind_app.hive_accounts fo ON fo.id = l.following
ORDER BY 1, 2;

\o muted.txt
SELECT fr.name, fo.name, l.block_num
FROM hivemind_app.muted l
JOIN hivemind_app.hive_accounts fr ON fr.id = l.follower
JOIN hivemind_app.hive_accounts fo ON fo.id = l.following
ORDER BY 1, 2;

\o blacklisted.txt
SELECT fr.name, fo.name, l.block_num
FROM hivemind_app.blacklisted l
JOIN hivemind_app.hive_accounts fr ON fr.id = l.follower
JOIN hivemind_app.hive_accounts fo ON fo.id = l.following
ORDER BY 1, 2;

\o follow_muted.txt
SELECT fr.name, fo.name, l.block_num
FROM hivemind_app.follow_muted l
JOIN hivemind_app.hive_accounts fr ON fr.id = l.follower
JOIN hivemind_app.hive_accounts fo ON fo.id = l.following
ORDER BY 1, 2;

\o follow_blacklisted.txt
SELECT fr.name, fo.name, l.block_num
FROM hivemind_app.follow_blacklisted l
JOIN hivemind_app.hive_accounts fr ON fr.id = l.follower
JOIN hivemind_app.hive_accounts fo ON fo.id = l.following
ORDER BY 1, 2;

-- Reblogs with their ids as drawn, and the feed cache
\o reblogs.txt
SELECT hr.id, ha.name, pk.k, hr.block_num, hr.created_at
FROM hivemind_app.hive_reblogs hr
JOIN hivemind_app.hive_accounts ha ON ha.id = hr.blogger_id
LEFT JOIN pk ON pk.id = hr.post_id
ORDER BY 1;

\o feed_cache.txt
SELECT ha.name, pk.k, f.block_num, f.created_at
FROM hivemind_app.hive_feed_cache f
JOIN hivemind_app.hive_accounts ha ON ha.id = f.account_id
LEFT JOIN pk ON pk.id = f.post_id
ORDER BY 1, 2;

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
UNION ALL SELECT 'accounts', count(*) FROM hivemind_app.hive_accounts
UNION ALL SELECT 'sum_post_count', sum(post_count) FROM hivemind_app.hive_accounts
UNION ALL SELECT 'follows', count(*) FROM hivemind_app.follows
UNION ALL SELECT 'muted', count(*) FROM hivemind_app.muted
UNION ALL SELECT 'reblogs', count(*) FROM hivemind_app.hive_reblogs
UNION ALL SELECT 'max_reblog_id', max(id) FROM hivemind_app.hive_reblogs
UNION ALL SELECT 'feed_cache', count(*) FROM hivemind_app.hive_feed_cache
UNION ALL SELECT 'last_completed', last_completed_block_num FROM hivemind_app.hive_state;
\o
