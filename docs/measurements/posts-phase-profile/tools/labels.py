"""Statement labels for the posts phase of hivemind massive sync (by query text prefix)."""

import re

LABELS = [
    ('posts_fn', r'^SELECT \* FROM hivemind_app.process_posts_from_staging'),
    ('pr_wave_comments', r'^INSERT INTO hivemind_app._post_results SELECT br.seq_id.*process_comments_batch'),
    ('pr_root', r'^INSERT INTO hivemind_app._post_results SELECT br.seq_id.*process_root_posts_batch'),
    ('hp_ins_comments', r'^WITH inserted AS \( INSERT INTO hivemind_app.hive_posts'),
    ('hp_ins_root', r'^WITH new_posts AS MATERIALIZED'),
    ('pb_ins_comments', r'^INSERT INTO hivemind_app._post_batch \(seq_id, author_id, permlink_id, parent_id'),
    ('pb_ins_root', r'^INSERT INTO hivemind_app._post_batch \(seq_id, author_id, permlink_id, category_id'),
    ('permlink_ins', r'^INSERT INTO hivemind_app.hive_permlink_data'),
    ('category_ins', r'^INSERT INTO hivemind_app.hive_category_data'),
    (
        'tags_5d',
        r'^SELECT hivemind_app.process_tags_batch\( ARRAY\( SELECT ROW\( base.post_id, tags.tag_val::VARCHAR, base.is_new_post',
    ),
    (
        'tags_5e',
        r'^SELECT hivemind_app.process_tags_batch\( ARRAY\( SELECT ROW\( base.post_id, tags.tag_val::VARCHAR, (false|\$)',
    ),
    ('tags_inner', r'^WITH inputs AS'),
    ('cs_ins', r'^INSERT INTO hivemind_app._comment_staging'),
    ('cs_norm', r'^UPDATE hivemind_app._comment_staging cs SET parent_author'),
    ('wave_count', r'^SELECT count\(\*\) FROM hivemind_app._comment_staging'),
    ('del_create_pairs', r'^_delete_create_pairs'),
    ('ineff_keys', r'^SELECT array_agg\(\(s.val'),
    ('edits_5b', r'^INSERT INTO hivemind_app._post_results SELECT cs.seq_id, pr_first'),
    ('edits_5c', r'^UPDATE hivemind_app.hive_posts hp SET updated_at = last_edit'),
    ('co_ops', r'^WITH co_ops AS'),
    ('simple_deletes', r'^WITH simple_delete_posts'),
    ('step7e', r'^WITH updateprops_type_changes'),
    (
        'step8_notif',
        r'^INSERT INTO hivemind_app.hive_notification_cache \(id, block_num, type_id, score, created_at, src, dst, post_id, dst_post_id, community',
    ),
    ('return_query', r'^SELECT \* FROM hivemind_app._post_results ORDER BY seq_id'),
    ('del_cs', r'^DELETE FROM hivemind_app._comment_staging'),
    ('del_pr', r'^DELETE FROM hivemind_app._post_results'),
    ('del_rp', r'^DELETE FROM hivemind_app._replay_pairs'),
    ('del_pb', r'^DELETE FROM hivemind_app._post_batch'),
    ('replay_pairs', r'^INSERT INTO hivemind_app._replay_pairs'),
    ('replay_loop', r'^SELECT cs.staging_id, cs.seq_id, 1 AS op_type_id'),
    ('delete_hive_post', r'delete_hive_post'),
    ('process_hive_post_op', r'process_hive_post_operation'),
]


def label_of(text: str) -> str | None:
    for name, rx in LABELS:
        if re.search(rx, text):
            return name
    return None
