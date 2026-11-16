\pset format unaligned
\pset tuples_only on
\pset fieldsep '\t'
select now(), (select current_block_num from hafd.contexts where name='hivemind_app'), c.relname, c.reltuples::bigint, pg_relation_size(c.oid), pg_total_relation_size(c.oid), coalesce(s.n_dead_tup,0), coalesce(s.autovacuum_count,0)
from pg_class c left join pg_stat_user_tables s on s.relid=c.oid where c.relnamespace='hivemind_app'::regnamespace and c.relkind='r' and c.relname in ('hive_posts','hive_post_data','hive_permlink_data','hive_votes','hive_post_tags','hive_accounts','hive_category_data','hive_tag_data','_post_batch','_comment_staging','_post_results','_ops_staging');
