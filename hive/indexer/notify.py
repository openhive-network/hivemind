"""Handle notifications"""

import logging

from hive.conf import SCHEMA_NAME
from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.indexer.notify_type import NotifyType
from hive.utils.misc import UniqueCounter, chunks
from hive.utils.normalize import escape_characters

# pylint: disable=too-many-lines,line-too-long

log = logging.getLogger(__name__)


class Notify(DbAdapterHolder):
    """Handles writing notifications/messages."""

    # pylint: disable=too-many-instance-attributes,too-many-arguments
    DEFAULT_SCORE = 35
    _notifies = []
    _notification_first_block = None
    _counter = UniqueCounter()
    _pending_lastread = {}  # {account_name: date_string} for batched massive sync updates

    def __init__(
        self,
        block_num,
        type_id,
        when=None,
        src_id=None,
        dst_id=None,
        community_id=None,
        post_id=None,
        payload=None,
        score=None,
        **kwargs,
    ):
        """Create a notification."""
        from hive.indexer.community import Community

        assert type_id, 'op is blank :('
        if isinstance(type_id, str):
            enum = NotifyType[type_id]
        elif isinstance(type_id, int):
            enum = NotifyType(type_id)
        else:
            raise Exception(f"unknown type {repr(type_id)}")

        self.block_num = block_num
        self.enum = enum
        self.score = score or self.DEFAULT_SCORE
        self.when = when
        self.src_id = src_id
        self.dst_id = dst_id
        self.post_id = post_id
        self.community_id = community_id
        self.payload = payload
        self._id = kwargs.get('id')
        self.counter = self._counter.increment(block_num)

        # This class is now only used for community logic, so we don't need to store notifications before
        if block_num >= Community.start_block:
            Notify._notifies.append(self)

    @classmethod
    def set_lastread(cls, account, date):
        """Update `lastread` column for a named account."""
        from hive.db.db_state import DbState

        if DbState.is_massive_sync():
            cls._pending_lastread[account] = date
        else:
            sql = f"UPDATE {SCHEMA_NAME}.hive_accounts SET lastread_at = :date WHERE name = :name"
            DbAdapterHolder.common_block_processing_db().query(sql, date=date, name=account)

    @classmethod
    def flush_lastread(cls):
        """Flush batched lastread updates in a single UPDATE."""
        if not cls._pending_lastread:
            return 0
        n = len(cls._pending_lastread)
        placeholders = ','.join(['(%s, %s::timestamp)'] * n)
        params = []
        for name, date in cls._pending_lastread.items():
            params.extend([name, date])
        sql = f"""UPDATE {SCHEMA_NAME}.hive_accounts ha
                  SET lastread_at = t.date
                  FROM (VALUES {placeholders}) AS t(name, date)
                  WHERE ha.name = t.name"""
        DbAdapterHolder.common_block_processing_db().query_no_return_raw(sql, tuple(params))
        cls._pending_lastread.clear()
        return n

    def to_db_values(self):
        """Generate a db row."""
        return "( {}, {}, {}, '{}'::timestamp, {}::int, {}::int, {}::int, {}::int, {}, {}::int )".format(
            self.block_num,
            self.enum.value,
            self.score,
            self.when if self.when else "NULL",
            self.src_id if self.src_id else "NULL",
            self.dst_id if self.dst_id else "NULL",
            self.post_id if self.post_id else "NULL",
            self.community_id if self.community_id else "NULL",
            escape_characters(str(self.payload)) if self.payload else "NULL",
            self.counter,
        )

    @classmethod
    def flush(cls):
        """Store buffered notifs"""

        n = len(Notify._notifies)
        if n > 0:
            if cls._notification_first_block is None:
                cls._notification_first_block = cls.db.query_row(
                    "select hivemind_app.block_before_irreversible( '90 days' ) AS num"
                )._mapping['num']
            max_block_num = max(n.block_num for n in Notify._notifies)
            cls.beginTx()

            sql_cache = f"""INSERT INTO {SCHEMA_NAME}.hive_notification_cache(
                            id, block_num, type_id, score, created_at,
                            src, dst, post_id, dst_post_id, community, community_title, payload)
                          SELECT {SCHEMA_NAME}.notification_id(n.created_at, n.type_id, n.counter), n.block_num, n.type_id, n.score, n.created_at, n.src, n.dst, n.post_id, n.post_id, hc.name, hc.title, n.payload
                          FROM
                          (VALUES {{}})
                          AS n(block_num, type_id, score, created_at, src, dst, post_id, community_id, payload, counter)
                          JOIN {SCHEMA_NAME}.hive_communities AS hc ON n.community_id = hc.id
                          WHERE n.score >= 0 AND n.src IS DISTINCT FROM n.dst
                                AND n.block_num > hivemind_app.block_before_irreversible('90 days')
                          ON CONFLICT (src, dst, type_id, post_id, block_num) DO NOTHING
                          """

            values = [notify.to_db_values() for notify in Notify._notifies]
            for chunk in chunks(values, 1000):
                joined_values = ','.join(chunk)
                if max_block_num > cls._notification_first_block:
                    cls.db.query_prepared(sql_cache.format(joined_values))

            Notify._notifies.clear()
            cls.commitTx()

        return n
