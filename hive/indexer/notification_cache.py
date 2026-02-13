"""Notification cache — flush methods now handled by SQL functions."""

from hive.indexer.db_adapter_holder import DbAdapterHolder


class NotificationCache(DbAdapterHolder):
    """Holds DB connection for parallel SQL notification/community processing."""


class VoteNotificationCache(NotificationCache):
    """Holds DB connection for parallel SQL vote notification flushing."""


class PostNotificationCache(NotificationCache):
    """Holds DB connection for parallel SQL post notification flushing."""


class FollowNotificationCache(NotificationCache):
    """Holds DB connection for parallel SQL follow notification flushing."""


class ReblogNotificationCache(NotificationCache):
    """Holds DB connection for parallel SQL reblog notification flushing."""
