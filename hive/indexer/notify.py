"""Handle notifications"""
import logging

from hive.conf import SCHEMA_NAME
from hive.db.adapter import Db
from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.utils.normalize import escape_characters
from hive.server.common.notify_type import NotifyType

# pylint: disable=too-many-lines,line-too-long

log = logging.getLogger(__name__)
DB = Db.instance()

class Notify(DbAdapterHolder):
    """Handles writing notifications/messages."""

    # pylint: disable=too-many-instance-attributes,too-many-arguments
    DEFAULT_SCORE = 35
    _notifies = []

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
        DB.query(sql, date=date, name=account)

    def to_db_values(self):
        """Generate a db row."""
        return "( {}, {}, {}, '{}'::timestamp, {}, {}, {}, {}, {} )".format(
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
    def flush(cls):
        """Store buffered notifs"""

        def execute_query(sql, values):
            values_str = ','.join(values)
            actual_query = sql.format(values_str)
            cls.db.query_prepared(actual_query)
            values.clear()

        n = 0
        if Notify._notifies:
            cls.beginTx()

            sql = f"""INSERT INTO {SCHEMA_NAME}.hive_notifs (block_num, type_id, score, created_at, src_id,
                                              dst_id, post_id, community_id,
                                              payload)
                          VALUES
                          -- block_num, type_id, score, created_at, src_id, dst_id, post_id, community_id, payload
                          {{}}"""

            values = []
            values_limit = 1000

            for notify in Notify._notifies:
                values.append(f"{notify.to_db_values()}")

                if len(values) >= values_limit:
                    execute_query(sql, values)

            if len(values) > 0:
                execute_query(sql, values)

            n = len(Notify._notifies)
            Notify._notifies.clear()
            cls.commitTx()

        return n
