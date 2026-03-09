"""Handle post subscription operations."""

import logging

from hive.conf import SCHEMA_NAME
from hive.indexer.accounts import Accounts
from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.utils.normalize import escape_characters

log = logging.getLogger(__name__)


class PostSubscription(DbAdapterHolder):
    """Handles post subscription operations (subscribe/unsubscribe to posts).

    Operations are collected during block processing and flushed in a single
    batch SQL call at the end of each block for performance.
    """

    # Batch collections: (subscriber_id, author, permlink, block_num, block_date)
    _subscribe_ops = []
    _unsubscribe_ops = []

    @classmethod
    def process_op(cls, account, op_json, block_date, block_num):
        """Process subscribe_post custom_json operation.

        Format: ["subscribe", {"author": "alice", "permlink": "my-post"}]
        or:     ["unsubscribe", {"author": "alice", "permlink": "my-post"}]

        Operations are collected and flushed in batch at end of block.
        """
        try:
            if not isinstance(op_json, list) or len(op_json) != 2:
                return

            command = op_json[0]
            payload = op_json[1]

            if command not in ('subscribe', 'unsubscribe'):
                return

            if not isinstance(payload, dict):
                return

            if 'author' not in payload or 'permlink' not in payload:
                return

            author = payload['author']
            permlink = payload['permlink']

            if not isinstance(author, str) or not isinstance(permlink, str):
                return

            if not author or not permlink:
                return

            # Validate accounts exist (in-memory check, fast)
            if not Accounts.exists(account):
                return

            if not Accounts.exists(author):
                return

            subscriber_id = Accounts.get_id(account)

            if command == 'subscribe':
                cls._subscribe_ops.append((subscriber_id, author, permlink, block_num, block_date))
            else:
                cls._unsubscribe_ops.append((subscriber_id, author, permlink, block_num))

        except Exception as e:
            log.warning("post_subscription op failed: %s in %s", e, op_json)

    @classmethod
    def flush(cls):
        """Flush subscribe operations only. Unsubscribes are deferred to flush_unsubscribes.

        This split allows notifications to be generated for comments created between
        a subscribe and unsubscribe in the same batch.
        """
        total = len(cls._subscribe_ops)
        if total == 0:
            return 0

        cls.beginTx()

        subscribe_values = []
        for subscriber_id, author, permlink, block_num, block_date in cls._subscribe_ops:
            subscribe_values.append(
                f"({subscriber_id}, {escape_characters(author)}, {escape_characters(permlink)}, {block_num}, '{block_date}'::timestamp)"
            )

        sql = f"""SELECT {SCHEMA_NAME}.flush_post_subscribes(
            ARRAY[{','.join(subscribe_values)}]::hivemind_app.post_subscription_op[]
        )"""
        cls.db.query_no_return(sql)

        cls._subscribe_ops.clear()
        cls.commitTx()
        return total

    @classmethod
    def flush_unsubscribes(cls):
        """Flush unsubscribe operations. Called AFTER notification generation."""
        total = len(cls._unsubscribe_ops)
        if total == 0:
            return 0

        cls.beginTx()

        unsubscribe_values = []
        for subscriber_id, author, permlink, block_num in cls._unsubscribe_ops:
            unsubscribe_values.append(
                f"({subscriber_id}, {escape_characters(author)}, {escape_characters(permlink)}, {block_num})"
            )

        sql = f"""SELECT {SCHEMA_NAME}.flush_post_unsubscribes(
            ARRAY[{','.join(unsubscribe_values)}]::hivemind_app.post_unsubscription_op[]
        )"""
        cls.db.query_no_return(sql)

        cls._unsubscribe_ops.clear()
        cls.commitTx()
        return total
