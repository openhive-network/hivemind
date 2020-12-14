"""Handles follow operations."""

import logging

from funcy.seqs import first
from hive.utils.misc import chunks
from hive.indexer.accounts import Accounts

from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.utils.normalize import escape_characters


log = logging.getLogger(__name__)

class Follow(DbAdapterHolder):
    """Handles processing of incoming follow ups and flushing to db."""

    follow_items_to_flush = dict()

    idx = 0

    @classmethod
    def is_blacklisted(cls, state):
        return state == 3

    @classmethod
    def is_follow_blacklists(cls, state):
        return state == 4

    @classmethod
    def is_follow_muted(cls, state):
        return state == 7

    @classmethod
    def get_mass_data_for_follower(cls, follower, state, block_num):
        def make_query(follower, additional_condition = None):
            """ Construct query for mass data operations for given follower """
            sql = """
                SELECT
                    ha_flr.name as follower,
                    ha_flg.name as following,
                    hf.created_at,
                    hf.state,
                    hf.blacklisted,
                    hf.follow_blacklists,
                    hf.follow_muted,
                    hf.block_num
                FROM
                    hive_follows hf
                INNER JOIN hive_accounts ha_flr ON hf.follower = ha_flr.id
                INNER JOIN hive_accounts ha_flg ON hf.following = ha_flg.id
                WHERE
                    ha_flr.name = {}
            """.format(follower)
            if additional_condition is not None and isinstance(additional_condition, str):
                sql += " " + additional_condition
            return sql

        def sql_to_follow_items_to_flush(sql, process_following_null = False):
            """ Convert data from sql query to follow_items_to_flush items """
            data = cls.db.query_all(sql)
            for row in data:
                flr = escape_characters(row['follower'])
                flg = escape_characters(row['following'])
                k = '{}/{}'.format(flr, flg)
                if k in cls.follow_items_to_flush:
                    cls.follow_items_to_flush[k]['idx'] = cls.idx
                    if state in (10, 11, 14) and not process_following_null:
                        cls.follow_items_to_flush[k]['state'] = 0
                    if state in (9, 14) and not process_following_null:
                        cls.follow_items_to_flush[k]['blacklisted'] = False
                    if state in (12, 14):
                        cls.follow_items_to_flush[k]['follow_blacklists'] = process_following_null
                    if state in (13, 14):
                        cls.follow_items_to_flush[k]['follow_muted'] = process_following_null
                    cls.follow_items_to_flush[k]['block_num'] = block_num
                else:
                    cls.follow_items_to_flush[k] = dict(
                        idx=cls.idx,
                        flr=flr,
                        flg=flg,
                        state=0 if state in (10, 11, 14) and not process_following_null else row['state'],
                        blacklisted=False if state in (9, 14) and not process_following_null else row['blacklisted'],
                        follow_blacklists=process_following_null if state in (12, 14) else row['follow_blacklists'],
                        follow_muted=process_following_null if state in (13, 14) else row['follow_muted'],
                        at=row['created_at'],
                        block_num=block_num
                    )
                cls.idx += 1

        if state in (9, 12, 13, 14):
            sql = make_query(follower)
            sql_to_follow_items_to_flush(sql)
        if state == 10:
            sql = make_query(follower, "AND hf.state = 1")
            sql_to_follow_items_to_flush(sql)
        if state == 11:
            sql = make_query(follower, "AND hf.state = 2")
            sql_to_follow_items_to_flush(sql)
        if state in (12, 13, 14):
            sql = make_query(follower, "AND ha_flg.name = 'null'")
            sql_to_follow_items_to_flush(sql, True)

    @classmethod
    def follow_op(cls, account, op_json, date, block_num):
        """Process an incoming follow op."""
        op = cls._validated_op(account, op_json, date)
        if not op:
            return
        op['block_num'] = block_num
        state = int(op['state'])

        if state > 8:
            cls.get_mass_data_for_follower(op['flr'], state, block_num)
        else:
            for following in op['flg']:
                k = '{}/{}'.format(op['flr'], following)
                # no k in cls.follow_items_to_flush but we have data in db
                if k not in cls.follow_items_to_flush:
                    sql = """
                        SELECT
                            *
                        FROM
                            hive_follows
                        WHERE 
                            follower = (SELECT id FROM hive_accounts WHERE name = {})
                            AND following = (SELECT id FROM hive_accounts WHERE name = {})
                    """
                    row = cls.db.query_row(sql.format(op['flr'], following))
                    if row is not None:
                        cls.follow_items_to_flush[k] = dict(
                            idx=cls.idx,
                            flr=op['flr'],
                            flg=following,
                            state=row[3],
                            blacklisted=row[5],
                            follow_blacklists=row[6],
                            follow_muted=row[7],
                            at=row[4],
                            block_num=row[8]
                        )
                    else:
                        cls.follow_items_to_flush[k] = dict(
                            idx=cls.idx,
                            flr=op['flr'],
                            flg=following,
                            state=state,
                            blacklisted=cls.is_blacklisted(state),
                            follow_blacklists=cls.is_follow_blacklists(state),
                            follow_muted=cls.is_follow_muted(state),
                            at=op['at'],
                            block_num=block_num
                        )
                cls.follow_items_to_flush[k]['idx'] = cls.idx
                cls.follow_items_to_flush[k]['state'] = state
                if state in (3, 5):
                    cls.follow_items_to_flush[k]['blacklisted'] = cls.is_blacklisted(state)

                if state in (4, 6):
                    cls.follow_items_to_flush[k]['follow_blacklists'] = cls.is_follow_blacklists(state)

                if state in (7, 8):
                    cls.follow_items_to_flush[k]['follow_muted'] = cls.is_follow_muted(state)

                cls.follow_items_to_flush[k]['block_num'] = block_num
                cls.idx += 1

    @classmethod
    def _validated_op(cls, account, op, date):
        """Validate and normalize the operation."""
        if (not 'what' in op
           or not isinstance(op['what'], list)
           or not 'follower' in op
           or not 'following' in op):
            return None

                # follower/following is empty
        if not op['follower'] or not op['following']:
            return None

        op['following'] = op['following'] if isinstance(op['following'], list) else [op['following']]

        # mimic original behaviour
        # if following name does not exist do not process it: basically equal to drop op for single following entry

        op['following'] = [op for op in op['following'] if Accounts.exists(op)]

        # if follower name does not exist drop op
        if not Accounts.exists(op['follower']):
            return None

        if op['follower'] in op['following'] or op['follower'] != account:
            return None

        what = first(op['what']) or ''
        if not isinstance(what, str):
            return None
        defs = {'': 0, 'blog': 1, 'ignore': 2, 'blacklist': 3, 'follow_blacklist': 4, 'unblacklist': 5, 'unfollow_blacklist': 6,
                'follow_muted': 7, 'unfollow_muted': 8, 'reset_blacklist' : 9, 'reset_following_list': 10, 'reset_muted_list': 11,
                'reset_follow_blacklist': 12, 'reset_follow_muted_list': 13, 'reset_all_lists': 14}
        if what not in defs:
            return None

        return dict(flr=escape_characters(op['follower']),
                    flg=[escape_characters(following) for following in op['following']],
                    state=defs[what],
                    at=date)

    @classmethod
    def flush(cls):
        n = 0
        if cls.follow_items_to_flush:
            sql = """
                INSERT INTO hive_follows as hf (follower, following, created_at, state, blacklisted, follow_blacklists, follow_muted, block_num)
                SELECT
                    ds.follower_id,
                    ds.following_id,
                    ds.created_at,
                    ds.state,
                    ds.blacklisted,
                    ds.follow_blacklists,
                    ds.follow_muted,
                    ds.block_num
                FROM
                (
                    SELECT
                        t.id,
                        ha_flr.id as follower_id,
                        ha_flg.id as following_id,
                        t.created_at,
                        t.state,
                        t.blacklisted,
                        t.follow_blacklists,
                        t.follow_muted,
                        t.block_num
                    FROM
                        (
                            VALUES
                            {}
                        ) as T (id, follower, following, created_at, state, blacklisted, follow_blacklists, follow_muted, block_num)
                    INNER JOIN hive_accounts ha_flr ON ha_flr.name = T.follower
                    INNER JOIN hive_accounts ha_flg ON ha_flg.name = T.following
                    ORDER BY T.block_num ASC, T.id ASC
                ) AS ds(id, follower_id, following_id, created_at, state, blacklisted, follow_blacklists, follow_muted, block_num)
                ORDER BY ds.block_num ASC, ds.id ASC
                ON CONFLICT ON CONSTRAINT hive_follows_ux1 DO UPDATE
                    SET
                        state = (CASE EXCLUDED.state
                                    WHEN 0 THEN 0 -- 0 blocks possibility to update state
                                    ELSE EXCLUDED.state
                                END),
                        blacklisted = EXCLUDED.blacklisted,
                        follow_blacklists = EXCLUDED.follow_blacklists,
                        follow_muted = EXCLUDED.follow_muted,
                        block_num = EXCLUDED.block_num
                WHERE hf.following = EXCLUDED.following AND hf.follower = EXCLUDED.follower
                """
            values = []
            limit = 1000
            count = 0

            cls.beginTx()
            for _, follow_item in cls.follow_items_to_flush.items():
                if count < limit:
                    values.append("({}, {}, {}, '{}'::timestamp, {}, {}, {}, {}, {})".format(follow_item['idx'],
                                                                          follow_item['flr'],
                                                                          follow_item['flg'],
                                                                          follow_item['at'],
                                                                          follow_item['state'],
                                                                          follow_item['blacklisted'],
                                                                          follow_item['follow_blacklists'],
                                                                          follow_item['follow_muted'],
                                                                          follow_item['block_num']))
                    count = count + 1
                else:
                    query = str(sql).format(",".join(values))
                    cls.db.query(query)
                    values.clear()
                    values.append("({}, {}, {}, '{}'::timestamp, {}, {}, {}, {}, {})".format(follow_item['idx'],
                                                                          follow_item['flr'],
                                                                          follow_item['flg'],
                                                                          follow_item['at'],
                                                                          follow_item['state'],
                                                                          follow_item['blacklisted'],
                                                                          follow_item['follow_blacklists'],
                                                                          follow_item['follow_muted'],
                                                                          follow_item['block_num']))
                    count = 1
                n += 1

            if len(values) > 0:
                query = str(sql).format(",".join(values))
                cls.db.query(query)
            cls.commitTx()
            cls.follow_items_to_flush.clear()
            cls.idx = 0
        return n
