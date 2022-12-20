""" Class for reblog operations """

import logging

from hive.conf import SCHEMA_NAME
from hive.db.adapter import Db
from hive.indexer.accounts import Accounts
from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.utils.normalize import escape_characters

log = logging.getLogger(__name__)
DB = Db.instance()


class Reblog(DbAdapterHolder):
    """Class for reblog operations"""

    reblog_items_to_flush = {}

    @classmethod
    def _validated_op(cls, actor, op, block_date, block_num):
        if 'account' not in op or 'author' not in op or 'permlink' not in op:
            return None

        if op['account'] != actor:
            return None  # impersonation

        if not Accounts.exists(op['account']):
            return None
        if not Accounts.exists(op['author']):
            return None

        _delete = True if ('delete' in op and op['delete'] == 'delete') else False

        return dict(
            author=op['author'],
            permlink=op['permlink'],
            account=op['account'],
            block_date=block_date,
            block_num=block_num,
            delete=_delete,
        )

    @classmethod
    def reblog_op(cls, actor, op, block_date, block_num):
        """Process reblog operation"""
        op = cls._validated_op(actor, op, block_date, block_num)
        if not op:
            return

        key = f"{op['author']}/{op['permlink']}/{op['account']}"

        if op['delete']:
            if key in cls.reblog_items_to_flush:
                del cls.reblog_items_to_flush[key]
            cls.delete(op['author'], op['permlink'], op['account'])
        else:
            cls.reblog_items_to_flush[key] = {'op': op}

    @classmethod
    def delete(cls, author, permlink, account):
        """Remove a reblog from hive_reblogs + feed from hive_feed_cache."""
        sql = f"SELECT {SCHEMA_NAME}.delete_reblog_feed_cache( (:author)::VARCHAR, (:permlink)::VARCHAR, (:account)::VARCHAR );"
        status = DB.query_col(sql, author=author, permlink=permlink, account=account)
        assert status is not None
        if status == 0:
            log.debug("reblog: post not found: %s/%s", author, permlink)

    @classmethod
    def flush(cls):
        """Flush collected data to database"""
        sql_prefix = f"""
            INSERT INTO {SCHEMA_NAME}.hive_reblogs (blogger_id, post_id, created_at, block_num)
            SELECT 
                data_source.blogger_id, data_source.post_id, data_source.created_at, data_source.block_num
            FROM
            (
                SELECT 
                    ha_b.id as blogger_id, hp.id as post_id, t.block_date as created_at, t.block_num 
                FROM
                    (VALUES
                        {{}}
                    ) AS T(blogger, author, permlink, block_date, block_num)
                    INNER JOIN {SCHEMA_NAME}.hive_accounts ha ON ha.name = t.author
                    INNER JOIN {SCHEMA_NAME}.hive_accounts ha_b ON ha_b.name = t.blogger
                    INNER JOIN {SCHEMA_NAME}.hive_permlink_data hpd ON hpd.permlink = t.permlink
                    INNER JOIN {SCHEMA_NAME}.hive_posts hp ON hp.author_id = ha.id AND hp.permlink_id = hpd.id AND hp.counter_deleted = 0
            ) AS data_source (blogger_id, post_id, created_at, block_num)
            ON CONFLICT ON CONSTRAINT hive_reblogs_ux1 DO NOTHING
        """

        item_count = len(cls.reblog_items_to_flush)
        if item_count > 0:
            values = []
            limit = 1000
            count = 0
            cls.beginTx()
            for k, v in cls.reblog_items_to_flush.items():
                reblog_item = v['op']
                if count < limit:
                    values.append(
                        f"({escape_characters(reblog_item['account'])}, {escape_characters(reblog_item['author'])}, {escape_characters(reblog_item['permlink'])}, '{reblog_item['block_date']}'::timestamp, {reblog_item['block_num']})"
                    )
                    count = count + 1
                else:
                    values_str = ",".join(values)
                    query = sql_prefix.format(values_str, values_str)
                    cls.db.query_prepared(query)
                    values.clear()
                    values.append(
                        f"({escape_characters(reblog_item['account'])}, {escape_characters(reblog_item['author'])}, {escape_characters(reblog_item['permlink'])}, '{reblog_item['block_date']}'::timestamp, {reblog_item['block_num']})"
                    )
                    count = 1

            if len(values) > 0:
                values_str = ",".join(values)
                query = sql_prefix.format(values_str, values_str)
                cls.db.query_prepared(query)
                values.clear()
            cls.commitTx()
            cls.reblog_items_to_flush.clear()

        return item_count
