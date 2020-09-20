""" Class for reblog operations """

import logging

from hive.db.adapter import Db
from hive.db.db_state import DbState

from hive.indexer.accounts import Accounts
from hive.indexer.feed_cache import FeedCache
from hive.indexer.notify import Notify
from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.utils.normalize import escape_characters

log = logging.getLogger(__name__)

DELETE_SQL = """
    WITH processing_set AS (
        SELECT hp.id as post_id, ha.id as account_id
        FROM hive_posts hp
        INNER JOIN hive_accounts ha ON hp.author_id = ha.id
        INNER JOIN hive_permlink_data hpd ON hp.permlink_id = hpd.id
        WHERE ha.name = :a AND hpd.permlink = :permlink AND hp.depth = 0 AND hp.counter_deleted = 0
    )
    DELETE FROM hive_reblogs AS hr
    WHERE hr.account = :a AND hr.post_id IN (SELECT ps.post_id FROM processing_set ps)
    RETURNING hr.post_id, (SELECT ps.account_id FROM processing_set ps) AS account_id
"""

class Reblog(DbAdapterHolder):
    """ Class for reblog operations """
    reblog_items_to_flush = []

    @classmethod
    def reblog_op(cls, account, op_json, block_date, block_num):
        """ Process reblog operation """
        if 'account' not in op_json or \
            'author' not in op_json or \
            'permlink' not in op_json:
            return

        blogger = op_json['account']
        author = op_json['author']
        permlink = escape_characters(op_json['permlink'])

        if blogger != account:
            return  # impersonation
        if not all(map(Accounts.exists, [author, blogger])):
            return

        if 'delete' in op_json and op_json['delete'] == 'delete':
            row = cls.db.query_row(DELETE_SQL, a=blogger, permlink=permlink)
            if row is None:
                log.debug("reblog: post not found: %s/%s", author, op_json['permlink'])
                return
            if not DbState.is_initial_sync():
                result = dict(row)
                FeedCache.delete(result['post_id'], result['account_id'])
        else:
            cls.reblog_items_to_flush.append((blogger, author, permlink, block_date, block_num))

    @classmethod
    def flush(cls):
        """ Flush collected data to database """
        sql_prefix = """
            INSERT INTO hive_reblogs (blogger_id, post_id, created_at, block_num)
            SELECT 
                data_source.blogger_id, data_source.post_id, data_source.created_at, data_source.block_num
            FROM
            (
                SELECT 
                    ha_b.id as blogger_id, hp.id as post_id, t.block_date as created_at, t.block_num 
                FROM
                    (VALUES
                        {}
                    ) AS T(blogger, author, permlink, block_date, block_num)
                    INNER JOIN hive_accounts ha ON ha.name = t.author
                    INNER JOIN hive_accounts ha_b ON ha_b.name = t.blogger
                    INNER JOIN hive_permlink_data hpd ON hpd.permlink = t.permlink
                    INNER JOIN hive_posts hp ON hp.author_id = ha.id AND hp.permlink_id = hpd.id
            ) AS data_source (blogger_id, post_id, created_at, block_num)
            ON CONFLICT ON CONSTRAINT hive_reblogs_ux1 DO NOTHING
        """

        item_count = len(cls.reblog_items_to_flush)
        if item_count > 0:
            values = []
            limit = 1000
            count = 0
            cls.beginTx()
            for reblog_item in cls.reblog_items_to_flush:
                if count < limit:
                    values.append("('{}', '{}', '{}', '{}'::timestamp, {})".format(reblog_item[0],
                                                                                   reblog_item[1],
                                                                                   reblog_item[2],
                                                                                   reblog_item[3],
                                                                                   reblog_item[4]))
                    count = count + 1
                else:
                    values_str = ",".join(values)
                    query = sql_prefix.format(values_str, values_str)
                    cls.db.query(query)
                    values.clear()
                    values.append("('{}', '{}', '{}', '{}'::timestamp, {})".format(reblog_item[0],
                                                                                   reblog_item[1],
                                                                                   reblog_item[2],
                                                                                   reblog_item[3],
                                                                                   reblog_item[4]))
                    count = 1

            if len(values) > 0:
                values_str = ",".join(values)
                query = sql_prefix.format(values_str, values_str)
                cls.db.query(query)
            cls.commitTx()
            cls.reblog_items_to_flush.clear()

        return item_count
