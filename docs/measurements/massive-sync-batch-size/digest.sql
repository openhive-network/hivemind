select t, n, h from (
select 'posts' t, count(*) n, sum(hashtext((to_jsonb(x))::text))::bigint h from hivemind_app.hive_posts x
union all select 'votes', count(*), sum(hashtext((to_jsonb(x)-'id')::text))::bigint from hivemind_app.hive_votes x
union all select 'accounts', count(*), sum(hashtext((to_jsonb(x))::text))::bigint from hivemind_app.hive_accounts x
union all select 'post_data', count(*), sum(hashtext((to_jsonb(x))::text))::bigint from hivemind_app.hive_post_data x
union all select 'permlinks', count(*), sum(hashtext((to_jsonb(x))::text))::bigint from hivemind_app.hive_permlink_data x
union all select 'follows', count(*), sum(hashtext((to_jsonb(x))::text))::bigint from hivemind_app.follows x
union all select 'reblogs', count(*), sum(hashtext((to_jsonb(x)-'id')::text))::bigint from hivemind_app.hive_reblogs x
union all select 'feed', count(*), sum(hashtext((to_jsonb(x))::text))::bigint from hivemind_app.hive_feed_cache x
union all select 'notif', count(*), sum(hashtext((to_jsonb(x)-'id')::text))::bigint from hivemind_app.hive_notification_cache x
union all select 'tags', count(*), sum(hashtext((to_jsonb(x))::text))::bigint from hivemind_app.hive_post_tags x
union all select 'mentions', count(*), sum(hashtext((to_jsonb(x)-'id')::text))::bigint from hivemind_app.hive_mentions x
union all select 'state', last_completed_block_num, (select current_block_num from hafd.contexts where name='hivemind_app') from hivemind_app.hive_state
) s;
