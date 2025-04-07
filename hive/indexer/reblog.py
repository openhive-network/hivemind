""" Class for reblog operations """

import logging
from collections import OrderedDict

from hive.conf import SCHEMA_NAME
from hive.db.adapter import Db
from hive.indexer.accounts import Accounts
from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.utils.normalize import escape_characters
from hive.utils.misc import chunks

log = logging.getLogger(__name__)

class Reblog(DbAdapterHolder):
    """Class for reblog operations"""

    reblog_items_to_flush = {}
    reblog_notifications_to_flush = OrderedDict()
    _notification_first_block = None

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
            cls.reblog_notifications_to_flush[key] = {
                    "block_num": block_num,
                    "created_at": block_date,
                    "src": op['account'],
                    "dst": op['author'],
                    "permlink": op['permlink'],
                }

    @classmethod
    def delete(cls, author, permlink, account):
        """Remove a reblog from hive_reblogs + feed from hive_feed_cache."""
        sql = f"SELECT {SCHEMA_NAME}.delete_reblog_feed_cache( (:author)::VARCHAR, (:permlink)::VARCHAR, (:account)::VARCHAR );"
        status = DbAdapterHolder.common_block_processing_db().query_col(sql, author=author, permlink=permlink, account=account)
        assert status is not None
        if status == 0:
            log.debug("reblog: post not found: %s/%s", author, permlink)

    @classmethod
    def flush(cls):
        return cls.flush_reblogs() + cls.flush_notifications()

    @classmethod
    def flush_reblogs(cls):
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

    @classmethod
    def flush_notifications(cls):
        if cls._notification_first_block is None:
            cls._notification_first_block = cls.db.query_row("select hivemind_app.block_before_irreversible( '90 days' ) AS num")['num']
        n = len(cls.reblog_notifications_to_flush)
        max_block_num = max(n['block_num'] for _,n in cls.reblog_notifications_to_flush.items() or [('', {"block_num": 0})])
        if n > 0 and max_block_num > cls._notification_first_block:
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
                (block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
                SELECT n.block_num, 14, n.created_at, r.id, g.id, pp.parent_id, p.id, COALESCE(rep.rep, 25), '', '', ''
                FROM
                (VALUES {{}})
                AS n(block_num, created_at, src, dst, permlink)
                JOIN {SCHEMA_NAME}.hive_accounts AS r ON n.src = r.name
                JOIN {SCHEMA_NAME}.hive_accounts AS g ON n.dst = g.name
                JOIN {SCHEMA_NAME}.hive_permlink_data AS p ON n.permlink = p.permlink
                JOIN {SCHEMA_NAME}.hive_posts AS pp ON pp.id = p.id
                LEFT JOIN final_rep AS rep ON r.haf_id = rep.account_id
                WHERE n.block_num > hivemind_app.block_before_irreversible( '90 days' )
                    AND COALESCE(rep.rep, 25) > 0
                    AND n.src IS DISTINCT FROM n.dst
                ORDER BY n.block_num, n.created_at, r.id, g.id, pp.parent_id, p.id
                ON CONFLICT (src, dst, type_id, post_id) DO UPDATE
                SET block_num=EXCLUDED.block_num, created_at=EXCLUDED.created_at
            """
            for chunk in chunks(cls.reblog_notifications_to_flush, 1000):
                cls.beginTx()
                values_str = ','.join(f"({n['block_num']}, {escape_characters(n['created_at'])}::timestamp, {escape_characters(n['src'])}, {escape_characters(n['dst'])}, {escape_characters(n['permlink'])})" for _,n in chunk.items())
                cls.db.query_prepared(sql.format(values_str))
                cls.commitTx()
        else:
            n = 0
        cls.reblog_notifications_to_flush.clear()
        return n

