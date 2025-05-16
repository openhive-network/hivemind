"""Handle notifications"""
import logging

from hive.conf import SCHEMA_NAME
from hive.db.adapter import Db
from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.utils.normalize import escape_characters
from hive.indexer.notify_type import NotifyType
from hive.utils.misc import chunks

# pylint: disable=too-many-lines,line-too-long

log = logging.getLogger(__name__)

class Notify(DbAdapterHolder):
    """Handles writing notifications/messages."""

    # pylint: disable=too-many-instance-attributes,too-many-arguments
    DEFAULT_SCORE = 35
    _notifies = []
    _notification_first_block = None

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

        # for HF24 we started save notifications from block 44300000
        # about 90 days before release day
        if block_num > 44300000:
            Notify._notifies.append(self)

    @classmethod
    def set_lastread(cls, account, date):
        """Update `lastread` column for a named account."""
        sql = f"UPDATE {SCHEMA_NAME}.hive_accounts SET lastread_at = :date WHERE name = :name"
        DbAdapterHolder.common_block_processing_db().query(sql, date=date, name=account)

    def to_db_values(self):
        """Generate a db row."""
        return "( {}, {}, {}, '{}'::timestamp, {}::int, {}::int, {}::int, {}::int, {} )".format(
            self.block_num,
            self.enum.value,
            self.score,
            self.when if self.when else "NULL",
            self.src_id if self.src_id else "NULL",
            self.dst_id if self.dst_id else "NULL",
            self.post_id if self.post_id else "NULL",
            self.community_id if self.community_id else "NULL",
            escape_characters(str(self.payload)) if self.payload else "NULL",
        )

    @classmethod
    def on_process_done(cls):
        """Called when current batch processing is complete"""
        pass

    @classmethod
    def flush(cls):
        """Store buffered notifs"""

        n = len(Notify._notifies)
        if n > 0:
            if cls._notification_first_block is None:
                cls._notification_first_block = cls.db.query_row("select hivemind_app.block_before_irreversible( '90 days' ) AS num")['num']
            max_block_num = max(n.block_num for n in Notify._notifies)
            cls.beginTx()

            sql_notifs = f"""INSERT INTO {SCHEMA_NAME}.hive_notifs (block_num, type_id, score, created_at, src_id,
                                              dst_id, post_id, community_id,
                                              payload)
                          VALUES
                          -- block_num, type_id, score, created_at, src_id, dst_id, post_id, community_id, payload
                          {{}}"""

            sql_cache = f"""INSERT INTO {SCHEMA_NAME}.hive_notification_cache (block_num, type_id, score, created_at,
                                              src, dst, post_id, dst_post_id, community, community_title, payload)
                          SELECT n.block_num, n.type_id, n.score, n.created_at, n.src, n.dst, n.post_id, n.post_id, hc.name, hc.title, n.payload
                          FROM
                          (VALUES {{}})
                          AS n(block_num, type_id, score, created_at, src, dst, post_id, community_id, payload)
                          JOIN {SCHEMA_NAME}.hive_communities AS hc ON n.community_id = hc.id
                          WHERE n.score >= 0 AND n.src IS DISTINCT FROM n.dst
                                AND n.block_num > hivemind_app.block_before_irreversible('90 days')
                          """

            values = [notify.to_db_values() for notify in Notify._notifies]
            for chunk in chunks(values, 1000):
                joined_values = ','.join(chunk)
                cls.db.query_prepared(sql_notifs.format(joined_values))
                if max_block_num > cls._notification_first_block:
                    cls.db.query_prepared(sql_cache.format(joined_values))

            Notify._notifies.clear()
            cls.commitTx()

        return n
