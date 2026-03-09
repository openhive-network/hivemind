"""Notification cache — flush methods now handled by SQL functions."""

from hive.conf import SCHEMA_NAME
from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.utils.normalize import escape_characters


class NotificationCache(DbAdapterHolder):
    """Holds DB connection for parallel SQL notification/community processing."""

    subscription_notifications_to_flush = []  # (post_id, author_id, block_num, block_date, counter)
    _notification_first_block = None

    @classmethod
    def notification_first_block(cls, db):
        if cls._notification_first_block is None:
            cls._notification_first_block = db.query_one(f"SELECT {SCHEMA_NAME}.block_before_irreversible( '90 days' )")
        return cls._notification_first_block


class VoteNotificationCache(NotificationCache):
    """Holds DB connection for parallel SQL vote notification flushing."""


class PostNotificationCache(NotificationCache):
    """Holds DB connection for parallel SQL post notification flushing."""


class FollowNotificationCache(NotificationCache):
    """Holds DB connection for parallel SQL follow notification flushing."""


class ReblogNotificationCache(NotificationCache):
    """Holds DB connection for parallel SQL reblog notification flushing."""


class SubscriptionNotificationCache(NotificationCache):
    """Handles flushing subscription notifications.

    This must run AFTER PostSubscription.flush() so subscriptions are in DB.
    After generating notifications, it also runs unsubscribes to guarantee
    subscription rows still exist during the notification query.
    """

    @classmethod
    def _resolve_pending_unsubscribes(cls):
        """Resolve pending unsubscribe ops to (subscriber_id, post_id, block_num) tuples.

        This allows notification generation to exclude subscribers who unsubscribed
        before a comment was created, even though the actual DELETE runs after.
        """
        from hive.indexer.post_subscription import PostSubscription

        if not PostSubscription._unsubscribe_ops:
            return [], [], []

        values = []
        for subscriber_id, author, permlink, block_num in PostSubscription._unsubscribe_ops:
            values.append(f"({subscriber_id}, {escape_characters(author)}, {escape_characters(permlink)}, {block_num})")

        rows = cls.db.query_all(
            f"SELECT op.subscriber_id, hp.id, op.block_num "
            f"FROM (VALUES {','.join(values)}) AS op(subscriber_id, author, permlink, block_num) "
            f"JOIN {SCHEMA_NAME}.hive_accounts ha ON ha.name = op.author::VARCHAR "
            f"JOIN {SCHEMA_NAME}.hive_permlink_data hpd ON hpd.permlink = op.permlink::VARCHAR "
            f"JOIN {SCHEMA_NAME}.hive_posts hp ON hp.author_id = ha.id AND hp.permlink_id = hpd.id "
            f"AND hp.counter_deleted = 0"
        )

        if not rows:
            return [], [], []

        sub_ids = [row[0] for row in rows]
        post_ids = [row[1] for row in rows]
        block_nums = [row[2] for row in rows]
        return sub_ids, post_ids, block_nums

    @classmethod
    def flush_subscription_notifications(cls):
        """Generate notifications for all batched posts that might have subscribers.

        Manages counters dynamically to avoid ID collisions when multiple posts
        in the same block each generate multiple notifications.
        """
        n = len(cls.subscription_notifications_to_flush)
        if n == 0:
            return 0

        # FAST PATH: Check if any subscriptions exist at all before processing
        # This avoids thousands of SQL calls when there are no subscriptions
        has_subscriptions = cls.db.query_one(
            f"SELECT EXISTS(SELECT 1 FROM {SCHEMA_NAME}.hive_post_subscriptions LIMIT 1)"
        )
        if not has_subscriptions:
            cls.subscription_notifications_to_flush.clear()
            return 0

        total_inserted = 0
        cls.beginTx()

        # Resolve pending unsubscribes so we can exclude subscribers who
        # unsubscribed before a comment was created (actual DELETE runs at the end of this method)
        unsub_sub_ids, unsub_post_ids, unsub_block_nums = cls._resolve_pending_unsubscribes()

        # Format arrays as SQL literals (all values are integers from DB, safe to inline)
        unsub_sids_sql = (
            "ARRAY[" + ",".join(str(x) for x in unsub_sub_ids) + "]::INTEGER[]"
            if unsub_sub_ids
            else "ARRAY[]::INTEGER[]"
        )
        unsub_pids_sql = (
            "ARRAY[" + ",".join(str(x) for x in unsub_post_ids) + "]::INTEGER[]"
            if unsub_post_ids
            else "ARRAY[]::INTEGER[]"
        )
        unsub_bnums_sql = (
            "ARRAY[" + ",".join(str(x) for x in unsub_block_nums) + "]::INTEGER[]"
            if unsub_block_nums
            else "ARRAY[]::INTEGER[]"
        )

        # Track counter per block to avoid ID collisions
        # Key: block_num, Value: next available counter
        block_counters = {}

        for post_id, author_id, block_num, block_date in cls.subscription_notifications_to_flush:
            if block_num <= NotificationCache.notification_first_block(cls.db):
                continue

            # Get or initialize counter for this block
            if block_num not in block_counters:
                block_counters[block_num] = 1
            counter = block_counters[block_num]

            result = cls.db.query_row(
                f"SELECT {SCHEMA_NAME}.generate_post_subscription_notifications("
                f":post_id, :author_id, :block_num, :block_date, :counter, "
                f"{unsub_sids_sql}, {unsub_pids_sql}, {unsub_bnums_sql})",
                post_id=post_id,
                author_id=author_id,
                block_num=block_num,
                block_date=block_date,
                counter=counter,
            )
            if result and result[0]:
                inserted_count = result[0]
                total_inserted += inserted_count
                # Advance counter by the number of notifications inserted
                block_counters[block_num] = counter + inserted_count

        cls.commitTx()
        cls.subscription_notifications_to_flush.clear()

        # Run unsubscribes AFTER notifications are generated, so subscription rows
        # still exist during the notification query above.
        from hive.indexer.post_subscription import PostSubscription

        PostSubscription.flush_unsubscribes()

        return total_inserted
