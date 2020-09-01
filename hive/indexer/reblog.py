""" Class for reblog operations """

import logging

from hive.db.adapter import Db
from hive.db.db_state import DbState

from hive.indexer.accounts import Accounts
from hive.indexer.feed_cache import FeedCache
from hive.indexer.notify import Notify
from hive.indexer.db_adapter_holder import DbAdapterHolder

log = logging.getLogger(__name__)

DELETE_SQL = """
    WITH processing_set AS (
        SELECT hp.id as post_id, ha.id as account_id
        FROM hive_posts hp
        INNER JOIN hive_accounts ha ON hp.author_id = ha.id
        INNER JOIN hive_permlink_data hpd ON hp.permlink_id = hpd.id
        WHERE ha.name = :a AND hpd.permlink = :permlink AND hp.depth <= 0
    )
    DELETE FROM hive_reblogs AS hr
    WHERE hr.account = :a AND hr.post_id IN (SELECT ps.post_id FROM processing_set ps)
    RETURNING hr.post_id, (SELECT ps.account_id FROM processing_set ps) AS account_id
"""

SELECT_SQL = """
    SELECT :blogger as blogger, hp.id as post_id, :date as date, :block_num as block_num
    FROM hive_posts hp
    INNER JOIN hive_accounts ha ON ha.id = hp.author_id
    INNER JOIN hive_permlink_data hpd ON hpd.id = hp.permlink_id
    WHERE ha.name = :author AND hpd.permlink = :permlink AND hp.depth <= 0
"""

INSERT_SQL = """
    INSERT INTO hive_reblogs (account, post_id, created_at, block_num)
""" + SELECT_SQL + """
    ON CONFLICT ON CONSTRAINT hive_reblogs_ux1 DO NOTHING
    RETURNING post_id
"""

class Reblog(DbAdapterHolder):
    """ Class for reblog operations """
    reblog_items_to_flush = []

    @classmethod
    def reblog_op(cls, account, op_json, block_date, block_num):
        if 'account' not in op_json or \
            'author' not in op_json or \
            'permlink' not in op_json:
            return

        blogger = op_json['account']
        author = op_json['author']
        permlink = op_json['permlink']

        if blogger != account:
            return  # impersonation
        if not all(map(Accounts.exists, [author, blogger])):
            return

        if 'delete' in op_json and op_json['delete'] == 'delete':
            row = cls.db.query_row(DELETE_SQL, a=blogger, permlink=permlink)
            if row is None:
                log.debug("reblog: post not found: %s/%s", author, permlink)
                return
            if not DbState.is_initial_sync():
                result = dict(row)
                FeedCache.delete(result['post_id'], result['account_id'])
        else:
            if DbState.is_initial_sync():
                row = cls.db.query_row(SELECT_SQL, blogger=blogger, author=author, permlink=permlink, date=block_date, block_num=block_num)
                if row is not None:
                    result = dict(row)
                    cls.reblog_items_to_flush.append(result)
            else:
                row = cls.db.query_row(INSERT_SQL, blogger=blogger, author=author, permlink=permlink, date=block_date, block_num=block_num)
                if row is not None:
                    author_id = Accounts.get_id(author)
                    blogger_id = Accounts.get_id(blogger)
                    result = dict(row)
                    post_id = result['post_id']
                    FeedCache.insert(post_id, blogger_id, block_date)
                else:
                    log.warning("Error in reblog: Insert operation returned `None` as `post_id`. Op details: {}".format(op_json))
    @classmethod
    def flush(cls):
        sql_prefix = """
            INSERT INTO hive_reblogs (account, post_id, created_at, block_num)
            VALUES
        """
        sql_postfix = """
            ON CONFLICT ON CONSTRAINT hive_reblogs_ux1 DO NOTHING
        """

        values = []
        limit = 1000
        count = 0
        item_count = len(cls.reblog_items_to_flush)

        for reblog_item in cls.reblog_items_to_flush:
            if count < limit:
                values.append("('{}', {}, '{}', {})".format(reblog_item["blogger"], reblog_item["post_id"], reblog_item["date"], reblog_item["block_num"]))
                count = count + 1
            else:
                query = sql_prefix + ",".join(values)
                query += sql_postfix
                cls.db.query(query)
                values.clear()
                values.append("('{}', {}, '{}', {})".format(reblog_item["blogger"], reblog_item["post_id"], reblog_item["date"], reblog_item["block_num"]))
                count = 1

        if len(values) > 0:
            query = sql_prefix + ",".join(values)
            query += sql_postfix
            cls.db.query(query)
        cls.reblog_items_to_flush.clear()
        return item_count
