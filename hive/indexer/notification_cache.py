"""Handle notification cache"""

import logging
import collections
import threading

from hive.conf import SCHEMA_NAME
from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.utils.normalize import escape_characters
from hive.utils.misc import chunks, UniqueCounter

# pylint: disable=too-many-lines,line-too-long

log = logging.getLogger(__name__)


class NotificationCache(DbAdapterHolder):
    """Handles writing to notification cache."""

    _lock = threading.Lock()
    _notification_first_block = None
    _counter = UniqueCounter()
    vote_notifications = collections.OrderedDict()
    comment_notifications = collections.OrderedDict()
    follow_notifications_to_flush = []
    reblog_notifications_to_flush = collections.OrderedDict()


    @classmethod
    def notification_first_block(cls, db):
        if cls._notification_first_block is None:
            with cls._lock:
                if cls._notification_first_block is None:
                    cls._notification_first_block = db.query_row(
                        f"select {SCHEMA_NAME}.block_before_irreversible( '90 days' ) AS num"
                    )['num']
        return cls._notification_first_block

    @classmethod
    def flush_vote_notifications(cls, flusher):
        n = len(cls.vote_notifications)
        max_block_num = max(
            n["block_num"]
            for k, n in (cls.vote_notifications or {"": {"block_num": 0}}).items()
        )
        if n > 0 and max_block_num > cls.notification_first_block(flusher.db):
            sql = f"""
                INSERT INTO {SCHEMA_NAME}.hive_notification_cache
                (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
                SELECT hn.id, hn.block_num, 17, hn.last_update AS created_at, hn.src, hn.dst, hn.post_id, hn.post_id, hn.score, {SCHEMA_NAME}.format_vote_value_payload(vote_value) as payload, '', ''
                FROM (
                    SELECT
                      {SCHEMA_NAME}.notification_id(n.last_update, 17, n.counter) AS id,
                      n.*,
                      hv.id AS src,
                      hpv.author_id AS dst,
                      hpv.id AS post_id,
                      {SCHEMA_NAME}.calculate_value_of_vote_on_post(hpv.payout + hpv.pending_payout, hpv.rshares, n.rshares) AS vote_value,
                      {SCHEMA_NAME}.calculate_notify_vote_score(hpv.payout + hpv.pending_payout, hpv.abs_rshares, n.rshares) AS score
                    FROM
                    (VALUES {{}})
                    AS n(block_num, voter, author, permlink, last_update, rshares, counter)
                    JOIN {SCHEMA_NAME}.hive_accounts AS hv ON n.voter = hv.name
                    JOIN {SCHEMA_NAME}.hive_accounts AS ha ON n.author = ha.name
                    JOIN {SCHEMA_NAME}.hive_permlink_data AS pd ON n.permlink = pd.permlink
                    JOIN (
                        SELECT hpvi.id, hpvi.permlink_id, hpvi.author_id, hpvi.payout, hpvi.pending_payout, hpvi.abs_rshares, hpvi.vote_rshares as rshares
                        FROM {SCHEMA_NAME}.hive_posts hpvi
                        WHERE hpvi.block_num > {SCHEMA_NAME}.block_before_head('97 days'::interval)
                            AND hpvi.counter_deleted = 0
                    ) AS hpv ON pd.id = hpv.permlink_id AND ha.id = hpv.author_id
                ) AS hn
                WHERE hn.block_num > {SCHEMA_NAME}.block_before_irreversible( '90 days' )
                    AND score >= 0
                    AND hn.src IS DISTINCT FROM hn.dst
                    AND hn.rshares >= 10e9
                    AND hn.vote_value >= 0.02
                ORDER BY hn.block_num, created_at, hn.src, hn.dst
                ON CONFLICT (src, dst, type_id, post_id, block_num) DO NOTHING
            """
            for chunk in chunks(cls.vote_notifications, 1000):
                flusher.beginTx()
                values_str = ",".join(
                    f"({n['block_num']}, {escape_characters(n['voter'])}, {escape_characters(n['author'])}, {escape_characters(n['permlink'])}, {escape_characters(n['last_update'])}::timestamp, {n['rshares']}, {n['counter']})"
                    for k, n in chunk.items()
                )
                flusher.db.query_prepared(sql.format(values_str))
                flusher.commitTx()
        else:
            n = 0
        cls.vote_notifications.clear()
        return n

    @classmethod
    def flush_post_notifications(cls, flusher):
        n = len(cls.comment_notifications)
        max_block_num = max(
            n["block_num"]
            for _, n in cls.comment_notifications.items() or [("", {"block_num": 0})]
        )
        if n > 0 and max_block_num > cls.notification_first_block(flusher.db):
            # With clause is inlined, modified call to reptracker_endpoints.get_account_reputation.
            # Reputation is multiplied by 7.5 rather than 9 to bring the max value to 100 rather than 115.
            # In case of reputation being 0, the score is set to 25 rather than 0.
            sql = f"""
            WITH log_account_rep AS
            (
                SELECT
                    account_id,
                    LOG(10, ABS(nullif(reputation, 0))) AS rep,
                    (CASE WHEN reputation < 0 THEN -1 ELSE 1 END) AS is_neg
                FROM reptracker_app.account_reputations
            ),
            calculate_rep AS
            (
                SELECT
                    account_id,
                    GREATEST(lar.rep - 9, 0) * lar.is_neg AS rep
                FROM log_account_rep lar
            ),
            final_rep AS
            (
                SELECT account_id, (cr.rep * 7.5 + 25)::INT AS rep FROM calculate_rep AS cr
            )
            INSERT INTO {SCHEMA_NAME}.hive_notification_cache
            (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
            SELECT {SCHEMA_NAME}.notification_id(n.created_at, n.type_id, n.counter) AS id, n.block_num, n.type_id, n.created_at, n.src, n.dst, n.dst_post_id, n.post_id, COALESCE(r.rep, 25), '', '', ''
            FROM
            (VALUES {{}})
            AS n(block_num, type_id, created_at, src, dst, dst_post_id, post_id, counter)
            JOIN {SCHEMA_NAME}.hive_accounts AS ha ON n.src = ha.id
            LEFT JOIN final_rep AS r ON ha.haf_id = r.account_id
            WHERE n.block_num > {SCHEMA_NAME}.block_before_irreversible( '90 days' )
                AND COALESCE(r.rep, 25) > 0
                AND n.src IS DISTINCT FROM n.dst
            ORDER BY n.block_num, n.type_id, n.created_at, n.src, n.dst, n.dst_post_id, n.post_id
            ON CONFLICT (src, dst, type_id, post_id, block_num) DO NOTHING
            """
            for chunk in chunks(cls.comment_notifications, 1000):
                flusher.beginTx()
                values_str = ",".join(
                    f"({n['block_num']}, {n['type_id']}, {escape_characters(n['created_at'])}::timestamp, {n['src']}, {n['dst']}, {n['dst_post_id']}, {n['post_id']}, {n['counter']})"
                    for _, n in chunk.items()
                )
                flusher.db.query_prepared(sql.format(values_str))
                flusher.commitTx()
        else:
            n = 0
        cls.comment_notifications.clear()

        return n

    @classmethod
    def flush_follow_notifications(cls, flusher):
        n = len(cls.follow_notifications_to_flush)
        max_block_num = max(
            block_num
            for r, g, block_num, counter in cls.follow_notifications_to_flush or [("", "", 0, 0)]
        )
        if n > 0 and max_block_num > cls.notification_first_block(flusher.db):
            # With clause is inlined, modified call to reptracker_endpoints.get_account_reputation.
            # Reputation is multiplied by 7.5 rather than 9 to bring the max value to 100 rather than 115.
            # In case of reputation being 0, the score is set to 25 rather than 0.
            sql = f"""
                WITH log_account_rep AS
                (
                    SELECT
                        account_id,
                        LOG(10, ABS(nullif(reputation, 0))) AS rep,
                        (CASE WHEN reputation < 0 THEN -1 ELSE 1 END) AS is_neg
                    FROM reptracker_app.account_reputations
                ),
                calculate_rep AS
                (
                    SELECT
                        account_id,
                        GREATEST(lar.rep - 9, 0) * lar.is_neg AS rep
                    FROM log_account_rep lar
                ),
                final_rep AS
                (
                    SELECT account_id, (cr.rep * 7.5 + 25)::INT AS rep FROM calculate_rep AS cr
                ),
                notification_data AS (
                    SELECT
                        n.src,
                        n.dst,
                        n.block_num,
                        n.counter,
                        (SELECT hb.created_at FROM {SCHEMA_NAME}.blocks_view hb WHERE hb.num = (n.block_num - 1)) AS created_at
                    FROM (VALUES {{}}) AS n(src, dst, block_num, counter)
                )
                INSERT INTO {SCHEMA_NAME}.hive_notification_cache
                (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
                SELECT {SCHEMA_NAME}.notification_id(nd.created_at, 15, nd.counter) AS id, nd.block_num, 15, nd.created_at, r.id, g.id, NULL, NULL, COALESCE(rep.rep, 25), '', '', ''
                FROM notification_data AS nd
                JOIN {SCHEMA_NAME}.hive_accounts AS r ON nd.src = r.name
                JOIN {SCHEMA_NAME}.hive_accounts AS g ON nd.dst = g.name
                LEFT JOIN final_rep AS rep ON r.haf_id = rep.account_id
                WHERE nd.block_num > {SCHEMA_NAME}.block_before_irreversible( '90 days' )
                    AND COALESCE(rep.rep, 25) > 0
                    AND nd.src IS DISTINCT FROM nd.dst
                ORDER BY nd.block_num, created_at, r.id, r.id
                ON CONFLICT (src, dst, type_id, post_id, block_num) DO NOTHING
            """
            for chunk in chunks(cls.follow_notifications_to_flush, 1000):
                flusher.beginTx()
                values_str = ",".join(
                    f"({follower}, {following}, {block_num}, {counter})"
                    for (follower, following, block_num, counter) in chunk
                )
                flusher.db.query_prepared(sql.format(values_str))
                flusher.commitTx()
        else:
            n = 0
        cls.follow_notifications_to_flush.clear()

        return n

    @classmethod
    def flush_reblog_notifications(cls, flusher):
        n = len(cls.reblog_notifications_to_flush)
        max_block_num = max(
            n["block_num"]
            for _, n in cls.reblog_notifications_to_flush.items() or [("", {"block_num": 0})]
        )
        if n > 0 and max_block_num > cls.notification_first_block(flusher.db):
            # With clause is inlined, modified call to reptracker_endpoints.get_account_reputation.
            # Reputation is multiplied by 7.5 rather than 9 to bring the max value to 100 rather than 115.
            # In case of reputation being 0, the score is set to 25 rather than 0.
            sql = f"""
                WITH log_account_rep AS
                (
                    SELECT
                        account_id,
                        LOG(10, ABS(nullif(reputation, 0))) AS rep,
                        (CASE WHEN reputation < 0 THEN -1 ELSE 1 END) AS is_neg
                    FROM reptracker_app.account_reputations
                ),
                calculate_rep AS
                (
                    SELECT
                        account_id,
                        GREATEST(lar.rep - 9, 0) * lar.is_neg AS rep
                    FROM log_account_rep lar
                ),
                final_rep AS
                (
                    SELECT account_id, (cr.rep * 7.5 + 25)::INT AS rep FROM calculate_rep AS cr
                )
                INSERT INTO {SCHEMA_NAME}.hive_notification_cache
                (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
                SELECT {SCHEMA_NAME}.notification_id(n.created_at, 14, n.counter) AS id, n.block_num, 14, n.created_at, r.id, g.id, pp.parent_id, pp.id, COALESCE(rep.rep, 25), '', '', ''
                FROM
                (VALUES {{}})
                AS n(block_num, created_at, src, dst, permlink, counter)
                JOIN {SCHEMA_NAME}.hive_accounts AS r ON n.src = r.name
                JOIN {SCHEMA_NAME}.hive_accounts AS g ON n.dst = g.name
                JOIN {SCHEMA_NAME}.hive_permlink_data AS p ON n.permlink = p.permlink
                JOIN {SCHEMA_NAME}.hive_posts AS pp ON pp.permlink_id = p.id AND pp.author_id = g.id AND pp.counter_deleted = 0
                LEFT JOIN final_rep AS rep ON r.haf_id = rep.account_id
                WHERE n.block_num > {SCHEMA_NAME}.block_before_irreversible( '90 days' )
                    AND COALESCE(rep.rep, 25) > 0
                    AND n.src IS DISTINCT FROM n.dst
                ORDER BY n.block_num, n.created_at, r.id, g.id, pp.parent_id, p.id
                ON CONFLICT (src, dst, type_id, post_id, block_num) DO NOTHING
            """
            for chunk in chunks(cls.reblog_notifications_to_flush, 1000):
                flusher.beginTx()
                values_str = ",".join(
                    f"({n['block_num']}, {escape_characters(n['created_at'])}::timestamp, {escape_characters(n['src'])}, {escape_characters(n['dst'])}, {escape_characters(n['permlink'])}, {n['counter']})"
                    for _, n in chunk.items()
                )
                flusher.db.query_prepared(sql.format(values_str))
                flusher.commitTx()
        else:
            n = 0
        cls.reblog_notifications_to_flush.clear()
        return n

    @classmethod
    def push_subscribe_notification(cls, params):
        if params["block_num"] > cls.notification_first_block(
            DbAdapterHolder.common_block_processing_db()
        ):
            params['counter'] = cls._counter.increment(params["block_num"])
            # With clause is inlined, modified call to reptracker_endpoints.get_account_reputation.
            # Reputation is multiplied by 7.5 rather than 9 to bring the max value to 100 rather than 115.
            # In case of reputation being 0, the score is set to 25 rather than 0.
            sql = f"""
                WITH log_account_rep AS
                (
                    SELECT
                        account_id,
                        LOG(10, ABS(nullif(reputation, 0))) AS rep,
                        (CASE WHEN reputation < 0 THEN -1 ELSE 1 END) AS is_neg
                    FROM reptracker_app.account_reputations
                ),
                calculate_rep AS
                (
                    SELECT
                        account_id,
                        GREATEST(lar.rep - 9, 0) * lar.is_neg AS rep
                    FROM log_account_rep lar
                ),
                final_rep AS
                (
                    SELECT account_id, (cr.rep * 7.5 + 25)::INT AS rep FROM calculate_rep AS cr
                )
                INSERT INTO {SCHEMA_NAME}.hive_notification_cache
                (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
                SELECT {SCHEMA_NAME}.notification_id(n.created_at, 11, n.counter), n.block_num, 11, n.created_at, r.id, hc.id, 0, 0, COALESCE(rep.rep, 25), '', hc.name, hc.title
                FROM
                (VALUES (:block_num, (:date)::timestamp, :actor_id, :community_id, :counter)) AS n(block_num, created_at, src, dst, counter)
                JOIN {SCHEMA_NAME}.hive_accounts AS r ON n.src = r.id
                JOIN {SCHEMA_NAME}.hive_communities AS hc ON n.dst = hc.id
                LEFT JOIN final_rep AS rep ON r.haf_id = rep.account_id
                WHERE n.block_num > {SCHEMA_NAME}.block_before_irreversible( '90 days' )
                    AND COALESCE(rep.rep, 25) > 0
                    AND n.src IS DISTINCT FROM n.dst
                ORDER BY n.block_num, n.created_at, r.id, hc.id
                ON CONFLICT (src, dst, type_id, post_id, block_num) DO NOTHING
            """
            DbAdapterHolder.common_block_processing_db().query_no_return(sql, **params)
