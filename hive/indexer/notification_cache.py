"""Handle notification cache"""

import collections
import logging
import threading

from hive.conf import SCHEMA_NAME
from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.utils.misc import UniqueCounter, chunks
from hive.utils.normalize import escape_characters

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

    _skip_accumulation = False
    _notification_min_block = None

    @classmethod
    def set_skip_accumulation(cls, skip):
        """Enable/disable skipping notification cache accumulation.

        During MASSIVE_WITHOUT_INDEXES, notifications are skipped because all blocks
        are far below the 90-day irreversible threshold and would never be flushed.
        Re-enabled when transitioning to MASSIVE_WITH_INDEXES or live mode.
        """
        cls._skip_accumulation = skip

    @classmethod
    def should_skip(cls):
        """Check if notification accumulation should be skipped."""
        return cls._skip_accumulation

    @classmethod
    def should_skip_for_block(cls, block_num):
        """Check if notification accumulation should be skipped for a given block.

        During MASSIVE_WITHOUT_INDEXES, only skip blocks older than the 90-day
        notification window. Recent blocks (e.g., mock data in CI) still need
        notifications accumulated.
        """
        if not cls._skip_accumulation:
            return False
        if cls._notification_min_block is None:
            cls._notification_min_block = cls.notification_first_block(cls.db)
        return block_num <= cls._notification_min_block

    @classmethod
    def notification_first_block(cls, db):
        if cls._notification_first_block is None:
            with cls._lock:
                if cls._notification_first_block is None:
                    cls._notification_first_block = db.query_row(
                        f"select {SCHEMA_NAME}.block_before_irreversible( '90 days' ) AS num"
                    )._mapping['num']
        return cls._notification_first_block


class VoteNotificationCache(NotificationCache):
    """Handles flushing vote notifications."""

    @classmethod
    def flush_vote_notifications(cls, force=False):
        if not force and not cls.vote_notifications and not cls._staging_table_created:
            return 0

        from hive.db.db_state import DbState

        if not force and DbState.is_massive_sync():
            return 0  # Defer to finalization; keep accumulated data

        n = len(cls.vote_notifications)
        max_block_num = max(n["block_num"] for k, n in (cls.vote_notifications or {"": {"block_num": 0}}).items())
        if n > 0 and max_block_num > NotificationCache.notification_first_block(cls.db):
            sql = f"""
                INSERT INTO {SCHEMA_NAME}.hive_notification_cache
                (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
                SELECT hn.id, hn.block_num, 17, hn.last_update AS created_at, hn.src, hn.dst, hn.post_id, hn.post_id, hn.score, {SCHEMA_NAME}.format_vote_value_payload(vote_value) as payload, '', ''
                FROM (
                    SELECT DISTINCT
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
                    LEFT JOIN {SCHEMA_NAME}.muted AS m ON m.follower = ha.id AND m.following = hv.id
                    LEFT JOIN {SCHEMA_NAME}.follow_muted AS fm ON fm.follower = ha.id
                    LEFT JOIN {SCHEMA_NAME}.muted AS mi ON mi.follower = fm.following AND mi.following = hv.id
                    JOIN (
                        SELECT hpvi.id, hpvi.permlink_id, hpvi.author_id, hpvi.payout, hpvi.pending_payout, hpvi.abs_rshares, hpvi.vote_rshares as rshares
                        FROM {SCHEMA_NAME}.hive_posts hpvi
                        WHERE hpvi.block_num > {SCHEMA_NAME}.block_before_head('97 days'::interval)
                            AND hpvi.counter_deleted = 0
                    ) AS hpv ON pd.id = hpv.permlink_id AND ha.id = hpv.author_id
                    WHERE m.follower IS NULL AND mi.following IS NULL
                ) AS hn
                WHERE hn.block_num > {SCHEMA_NAME}.block_before_irreversible( '90 days' )
                    AND score >= 0
                    AND hn.src IS DISTINCT FROM hn.dst
                    AND hn.rshares >= 10e9
                    AND hn.vote_value >= 0.02
                ORDER BY hn.block_num, created_at, hn.src, hn.dst
                ON CONFLICT DO NOTHING
            """
            for chunk in chunks(cls.vote_notifications, 1000):
                cls.beginTx()
                values_str = ",".join(
                    f"({n['block_num']}, {escape_characters(n['voter'])}, {escape_characters(n['author'])}, {escape_characters(n['permlink'])}, {escape_characters(n['last_update'])}::timestamp, {n['rshares']}, {n['counter']})"
                    for k, n in chunk.items()
                )
                cls.db.query_prepared(sql.format(values_str))
                cls.commitTx()
        else:
            n = 0
        cls.vote_notifications.clear()
        return n


class PostNotificationCache(NotificationCache):
    """Handles flushing post notifications."""

    @classmethod
    def flush_post_notifications(cls):
        n = len(cls.comment_notifications)
        max_block_num = max(n["block_num"] for _, n in cls.comment_notifications.items() or [("", {"block_num": 0})])
        if n > 0 and max_block_num > NotificationCache.notification_first_block(cls.db):
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
            SELECT DISTINCT {SCHEMA_NAME}.notification_id(n.created_at, n.type_id, n.counter) AS id, n.block_num, n.type_id, n.created_at, n.src, n.dst, n.dst_post_id, n.post_id, COALESCE(r.rep, 25), '', '', ''
            FROM
            (VALUES {{}})
            AS n(block_num, type_id, created_at, src, dst, dst_post_id, post_id, counter)
            JOIN {SCHEMA_NAME}.hive_accounts AS ha ON n.src = ha.id
            LEFT JOIN {SCHEMA_NAME}.muted AS m ON m.follower = n.dst AND m.following = n.src
            LEFT JOIN {SCHEMA_NAME}.follow_muted AS fm ON fm.follower = n.dst
            LEFT JOIN {SCHEMA_NAME}.muted AS mi ON mi.follower = fm.following AND mi.following = n.src
            LEFT JOIN final_rep AS r ON ha.haf_id = r.account_id
            WHERE n.block_num > {SCHEMA_NAME}.block_before_irreversible( '90 days' )
                AND COALESCE(r.rep, 25) > 0
                AND n.src IS DISTINCT FROM n.dst
                AND m.follower IS NULL AND mi.following IS NULL
            ORDER BY n.block_num, n.type_id, n.created_at, n.src, n.dst, n.dst_post_id, n.post_id
            ON CONFLICT DO NOTHING
            """
            for chunk in chunks(cls.comment_notifications, 10000):
                cls.beginTx()
                values_str = ",".join(
                    f"({n['block_num']}, {n['type_id']}, {escape_characters(n['created_at'])}::timestamp, {n['src']}, {n['dst']}, {n['dst_post_id']}, {n['post_id']}, {n['counter']})"
                    for _, n in chunk.items()
                )
                cls.db.query_prepared(sql.format(values_str))
                cls.commitTx()
        else:
            n = 0
        cls.comment_notifications.clear()

        return n


class FollowNotificationCache(NotificationCache):
    """Handles flushing follow notifications."""

    @classmethod
    def flush_follow_notifications(cls):
        n = len(cls.follow_notifications_to_flush)
        max_block_num = max(
            block_num for r, g, block_num, counter in cls.follow_notifications_to_flush or [("", "", 0, 0)]
        )
        if n > 0 and max_block_num > NotificationCache.notification_first_block(cls.db):
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
                        hb.created_at
                    FROM (VALUES {{}}) AS n(src, dst, block_num, counter)
                    LEFT JOIN {SCHEMA_NAME}.blocks_view hb ON hb.num = (n.block_num - 1)
                )
                INSERT INTO {SCHEMA_NAME}.hive_notification_cache
                (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
                SELECT DISTINCT {SCHEMA_NAME}.notification_id(nd.created_at, 15, nd.counter) AS id, nd.block_num, 15, nd.created_at, r.id, g.id, NULL::integer, NULL::integer, COALESCE(rep.rep, 25), '', '', ''
                FROM notification_data AS nd
                JOIN {SCHEMA_NAME}.hive_accounts AS r ON nd.src = r.name
                JOIN {SCHEMA_NAME}.hive_accounts AS g ON nd.dst = g.name
                LEFT JOIN {SCHEMA_NAME}.muted AS m ON m.follower = g.id AND m.following = r.id
                LEFT JOIN {SCHEMA_NAME}.follow_muted AS fm ON fm.follower = g.id
                LEFT JOIN {SCHEMA_NAME}.muted AS mi ON mi.follower = fm.following AND mi.following = r.id
                LEFT JOIN final_rep AS rep ON r.haf_id = rep.account_id
                WHERE nd.block_num > {SCHEMA_NAME}.block_before_irreversible( '90 days' )
                    AND COALESCE(rep.rep, 25) > 0
                    AND nd.src IS DISTINCT FROM nd.dst
                    AND m.follower IS NULL AND mi.following IS NULL
                ORDER BY nd.block_num, created_at, r.id, r.id
                ON CONFLICT DO NOTHING
            """
            for chunk in chunks(cls.follow_notifications_to_flush, 10000):
                cls.beginTx()
                values_str = ",".join(
                    f"({follower}, {following}, {block_num}, {counter})"
                    for (follower, following, block_num, counter) in chunk
                )
                cls.db.query_prepared(sql.format(values_str))
                cls.commitTx()
        else:
            n = 0
        cls.follow_notifications_to_flush.clear()

        return n


class ReblogNotificationCache(NotificationCache):
    """Handles flushing reblog notifications."""

    @classmethod
    def flush_reblog_notifications(cls):
        n = len(cls.reblog_notifications_to_flush)
        max_block_num = max(
            n["block_num"] for _, n in cls.reblog_notifications_to_flush.items() or [("", {"block_num": 0})]
        )
        if n > 0 and max_block_num > NotificationCache.notification_first_block(cls.db):
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
                SELECT DISTINCT {SCHEMA_NAME}.notification_id(n.created_at, 14, n.counter) AS id, n.block_num, 14, n.created_at, r.id, g.id, pp.parent_id, pp.id, COALESCE(rep.rep, 25), '', '', ''
                FROM
                (VALUES {{}})
                AS n(block_num, created_at, src, dst, permlink, counter)
                JOIN {SCHEMA_NAME}.hive_accounts AS r ON n.src = r.name
                JOIN {SCHEMA_NAME}.hive_accounts AS g ON n.dst = g.name
                JOIN {SCHEMA_NAME}.hive_permlink_data AS p ON n.permlink = p.permlink
                JOIN {SCHEMA_NAME}.hive_posts AS pp ON pp.permlink_id = p.id AND pp.author_id = g.id AND pp.counter_deleted = 0
                LEFT JOIN {SCHEMA_NAME}.muted AS m ON m.follower = g.id AND m.following = r.id
                LEFT JOIN {SCHEMA_NAME}.follow_muted AS fm ON fm.follower = g.id
                LEFT JOIN {SCHEMA_NAME}.muted AS mi ON mi.follower = fm.following AND mi.following = r.id
                LEFT JOIN final_rep AS rep ON r.haf_id = rep.account_id
                WHERE n.block_num > {SCHEMA_NAME}.block_before_irreversible( '90 days' )
                    AND COALESCE(rep.rep, 25) > 0
                    AND n.src IS DISTINCT FROM n.dst
                    AND m.follower IS NULL AND mi.following IS NULL
                ORDER BY n.block_num, n.created_at, r.id, g.id, pp.parent_id, pp.id
                ON CONFLICT DO NOTHING
            """
            for chunk in chunks(cls.reblog_notifications_to_flush, 1000):
                cls.beginTx()
                values_str = ",".join(
                    f"({n['block_num']}, {escape_characters(n['created_at'])}::timestamp, {escape_characters(n['src'])}, {escape_characters(n['dst'])}, {escape_characters(n['permlink'])}, {n['counter']})"
                    for _, n in chunk.items()
                )
                cls.db.query_prepared(sql.format(values_str))
                cls.commitTx()
        else:
            n = 0
        cls.reblog_notifications_to_flush.clear()
        return n
