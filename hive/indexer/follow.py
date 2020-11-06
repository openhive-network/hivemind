"""Handles follow operations."""

import logging
from time import perf_counter as perf
from json import dumps

from funcy.seqs import first
from hive.db.adapter import Db
from hive.db.db_state import DbState
from hive.utils.misc import chunks
from hive.indexer.accounts import Accounts

from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.utils.normalize import escape_characters


log = logging.getLogger(__name__)

FOLLOWERS = 'followers'
FOLLOWING = 'following'

DB = Db.instance()

def _flip_dict(dict_to_flip):
    """Swap keys/values. Returned dict values are array of keys."""
    flipped = {}
    for key, value in dict_to_flip.items():
        if value in flipped:
            flipped[value].append(key)
        else:
            flipped[value] = [key]
    return flipped

class Follow(DbAdapterHolder):
    """Handles processing of incoming follow ups and flushing to db."""

    follow_items_to_flush = dict()

    # [DK] this dictionary will hold data for table update operations
    # since for each status update query is different we will group
    # follower id per status:
    # {
    #   state_number_1 : [follower_id_1, follower_id_2, ...]
    #   state_number_2 : [follower_id_3, follower_id_4, ...]
    # }
    # we will use this dict later to perform batch updates
    follow_update_items_to_flush = dict()

    idx = 0

    @classmethod
    def follow_op(cls, account, op_json, date, block_num):
        """Process an incoming follow op."""
        op = cls._validated_op(account, op_json, date)
        if not op:
            return
        op['block_num'] = block_num

        state = op['state']

        for following in op['flg']:
            k = '{}/{}'.format(op['flr'], following)
            if k in cls.follow_items_to_flush:
                cls.follow_items_to_flush[k]['state'] = state
                cls.follow_items_to_flush[k]['idx'] = cls.idx
                cls.follow_items_to_flush[k]['block_num'] = block_num
            else:
                cls.follow_items_to_flush[k] = dict(
                    idx=cls.idx,
                    flr=op['flr'],
                    flg=following,
                    state=state,
                    at=op['at'],
                    block_num=block_num)
            cls.idx += 1

        if not DbState.is_initial_sync():
            for following in op['flg']:
                new_state = state
                old_state = cls._get_follow_db_state(op['flr'], following)
                if new_state == 1:
                    Follow.follow(op['flr'], following)
                if old_state == 1:
                    Follow.unfollow(op['flr'], following)

        if state > 8:
            # check if given state exists in dict
            # if exists add follower to a list for a given state
            # if not exists create list and set that list for given state
            if state in cls.follow_update_items_to_flush:
                cls.follow_update_items_to_flush[state].append(op['flr'])
            else:
                cls.follow_update_items_to_flush[state] = [op['flr']]

    @classmethod
    def _validated_op(cls, account, op, date):
        """Validate and normalize the operation."""
        if ( not 'what' in op
           or not isinstance(op['what'], list)
           or not 'follower' in op
           or not 'following' in op):
            return None

        op['following'] = op['following'] if isinstance(op['following'], list) else [op['following']]
        
        # additional layer of protection against putting complex data types as user names
        # we expecting follower and following entries to be strings
        # in older hivemind this check was done in Accounts.exists
        # now following can be list of names so we need to check if all entries are strings
        for following in op['following']:
            if not isinstance(following, str):
                return None

        if not isinstance(op['follower'], str):
            return None

        # follower/following is empty
        if not op['follower'] or not op['following']:
            return None

        what = first(op['what']) or ''
        if not isinstance(what, str):
            return None
        defs = {'': 0, 'blog': 1, 'ignore': 2, 'blacklist': 3, 'follow_blacklist': 4, 'unblacklist': 5, 'unfollow_blacklist': 6,
                'follow_muted': 7, 'unfollow_muted': 8, 'reset_blacklist' : 9, 'reset_following_list': 10, 'reset_muted_list': 11,
                'reset_follow_blacklist': 12, 'reset_follow_muted_list': 13, 'reset_all_lists': 14}
        if what not in defs:
            return None

        all_accounts = list(op['following'])
        all_accounts.append(op['follower'])
        if (op['follower'] in op['following']
            or op['follower'] != account):
            return None

        non_existent_names = Accounts.check_names(all_accounts)
        if non_existent_names:
            log.warning("Follow op validation, following names does not exists in database: {}".format(non_existent_names))

        return dict(flr=escape_characters(op['follower']),
                    flg=[escape_characters(following) for following in op['following']],
                    state=defs[what],
                    at=date)

    @classmethod
    def _get_follow_db_state(cls, follower, following):
        """Retrieve current follow state of an account pair."""
        sql = """
            SELECT
                state
            FROM
                hive_follows hf
            INNER JOIN hive_accounts ha_flr ON ha_flr.id = hf.follower AND ha_flr.name = :follower
            INNER JOIN hive_accounts ha_flg ON ha_flg.id = hf.following AND ha_flg.name = :following
        """
        return cls.db.query_one(sql, follower=follower, following=following)

    # -- stat tracking --

    _delta = {FOLLOWERS: {}, FOLLOWING: {}}

    @classmethod
    def follow(cls, follower, following):
        """Applies follow count change the next flush."""
        cls._apply_delta(follower, FOLLOWING, 1)
        cls._apply_delta(following, FOLLOWERS, 1)

    @classmethod
    def unfollow(cls, follower, following):
        """Applies follow count change the next flush."""
        cls._apply_delta(follower, FOLLOWING, -1)
        cls._apply_delta(following, FOLLOWERS, -1)

    @classmethod
    def _apply_delta(cls, account, role, direction):
        """Modify an account's follow delta in specified direction."""
        if not account in cls._delta[role]:
            cls._delta[role][account] = 0
        cls._delta[role][account] += direction

    @classmethod
    def _flush_follow_items(cls):
        n = 0
        if cls.follow_items_to_flush:
            sql_prefix = """
                INSERT INTO hive_follows as hf (follower, following, created_at, state, blacklisted, follow_blacklists, follow_muted, block_num)
                SELECT ds.follower_id, ds.following_id, ds.created_at, ds.state, ds.blacklisted, ds.follow_blacklists, ds.follow_muted, ds.block_num
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
            """
            sql_postfix = """
                ON CONFLICT ON CONSTRAINT hive_follows_ux1 DO UPDATE
                    SET
                        state = (CASE EXCLUDED.state
                                    WHEN 0 THEN 0 -- 0 blocks possibility to update state
                                    ELSE EXCLUDED.state
                                END),
                        blacklisted = (CASE EXCLUDED.state
                                        WHEN 3 THEN TRUE
                                        WHEN 5 THEN FALSE
                                        ELSE EXCLUDED.blacklisted
                                    END),
                        follow_blacklists = (CASE EXCLUDED.state
                                                WHEN 4 THEN TRUE
                                                WHEN 6 THEN FALSE
                                                ELSE EXCLUDED.follow_blacklists
                                            END),
                        follow_muted = (CASE EXCLUDED.state
                                           WHEN 7 THEN TRUE
                                           WHEN 8 THEN FALSE
                                           ELSE EXCLUDED.follow_muted
                                        END)
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
                                                                          follow_item['state'] == 3,
                                                                          follow_item['state'] == 4,
                                                                          follow_item['state'] == 7,
                                                                          follow_item['block_num']))
                    count = count + 1
                else:
                    query = str(sql_prefix).format(",".join(values))
                    query += sql_postfix
                    cls.db.query(query)
                    values.clear()
                    values.append("({}, {}, {}, '{}'::timestamp, {}, {}, {}, {}, {})".format(follow_item['idx'],
                                                                          follow_item['flr'],
                                                                          follow_item['flg'],
                                                                          follow_item['at'],
                                                                          follow_item['state'],
                                                                          follow_item['state'] == 3,
                                                                          follow_item['state'] == 4,
                                                                          follow_item['state'] == 7,
                                                                          follow_item['block_num']))
                    count = 1
                n += 1

            if len(values) > 0:
                query = str(sql_prefix).format(",".join(values))
                query += sql_postfix
                cls.db.query(query)
            cls.commitTx()
            cls.follow_items_to_flush.clear()

            # process follow_update_items_to_flush dictionary
            # .items() will return list of tuples: [(state_number, [list of follower ids]), ...]
            # for each state get list of follower_id and make update query
            # for that list, if list size is greater than 1000 it will be divided
            # to chunks of 1000
            #
            for state, update_flush_items in cls.follow_update_items_to_flush.items():
                for chunk in chunks(update_flush_items, 1000):
                    sql = None
                    query_values = ','.join(["({})".format(account) for account in chunk])
                    # [DK] probaly not a bad idea to move that logic to SQL function
                    if state == 9:
                        #reset blacklists for follower
                        sql = """
                            UPDATE
                                hive_follows hf
                            SET
                                blacklisted = false
                            FROM
                            (
                                SELECT
                                    ha.id as follower_id
                                FROM
                                    (
                                        VALUES
                                        {}
                                    ) AS T(name)
                                INNER JOIN hive_accounts ha ON ha.name = T.name
                            ) AS ds (follower_id)
                            WHERE
                                hf.follower = ds.follower_id
                        """.format(query_values)
                    elif state == 10:
                        #reset following list for follower
                        sql = """
                            UPDATE
                                hive_follows hf
                            SET
                                state = 0
                            FROM
                            (
                                SELECT
                                    ha.id as follower_id
                                FROM
                                    (
                                        VALUES
                                        {}
                                    ) AS T(name)
                                INNER JOIN hive_accounts ha ON ha.name = T.name
                            ) AS ds (follower_id)
                            WHERE
                                hf.follower = ds.follower_id
                                AND hf.state = 1
                        """.format(query_values)
                    elif state == 11:
                        #reset all muted list for follower
                        sql = """
                            UPDATE
                                hive_follows hf
                            SET
                                state = 0
                            FROM
                            (
                                SELECT
                                    ha.id as follower_id
                                FROM
                                    (
                                        VALUES
                                        {}
                                    ) AS T(name)
                                INNER JOIN hive_accounts ha ON ha.name = T.name
                            ) AS ds (follower_id)
                            WHERE
                                hf.follower = ds.follower_id
                                AND hf.state = 2
                        """.format(query_values)
                    elif state == 12:
                        #reset followed blacklists
                        sql = """
                            UPDATE
                                hive_follows hf
                            SET
                                follow_blacklists = false
                            FROM
                            (
                                SELECT
                                    ha.id as follower_id
                                FROM
                                    (
                                        VALUES
                                        {0}
                                    ) AS T(name)
                                INNER JOIN hive_accounts ha ON ha.name = T.name
                            ) AS ds (follower_id)
                            WHERE
                                hf.follower = ds.follower_id;

                            UPDATE
                                hive_follows hf
                            SET
                                follow_blacklists = true
                            FROM
                            (
                                SELECT
                                    ha.id as follower_id
                                FROM
                                    (
                                        VALUES
                                        {0}
                                    ) AS T(name)
                                INNER JOIN hive_accounts ha ON ha.name = T.name
                            ) AS ds (follower_id)
                            WHERE
                                hf.follower = ds.follower_id
                                AND following = (SELECT id FROM hive_accounts WHERE name = 'null')
                        """.format(query_values)

                    elif state == 13:
                        #reset followed mute lists
                        sql = """
                            UPDATE
                                hive_follows hf
                            SET
                                follow_muted = false
                            FROM
                            (
                                SELECT
                                    ha.id as follower_id
                                FROM
                                    (
                                        VALUES
                                        {0}
                                    ) AS T(name)
                                INNER JOIN hive_accounts ha ON ha.name = T.name
                            ) AS ds (follower_id)
                            WHERE
                                hf.follower = ds.follower_id;

                            UPDATE
                                hive_follows hf
                            SET
                                follow_muted = true
                            FROM
                            (
                                SELECT
                                    ha.id as follower_id
                                FROM
                                    (
                                        VALUES
                                        {0}
                                    ) AS T(name)
                                INNER JOIN hive_accounts ha ON ha.name = T.name
                            ) AS ds (follower_id)
                            WHERE
                                hf.follower = ds.follower_id
                                AND following = (SELECT id FROM hive_accounts WHERE name = 'null')
                        """.format(query_values)
                    elif state == 14:
                        #reset all lists
                        sql = """
                            UPDATE
                                hive_follows hf
                            SET
                                blacklisted = false,
                                follow_blacklists = false,
                                follow_muted = false,
                                state = 0
                            FROM
                            (
                                SELECT
                                    ha.id as follower_id
                                FROM
                                    (
                                        VALUES
                                        {0}
                                    ) AS T(name)
                                INNER JOIN hive_accounts ha ON ha.name = T.name
                            ) AS ds (follower_id)
                            WHERE
                                hf.follower = ds.follower_id;

                            UPDATE
                                hive_follows hf
                            SET
                                follow_blacklists = true,
                                follow_muted = true
                            FROM
                            (
                                SELECT
                                    ha.id as follower_id
                                FROM
                                    (
                                        VALUES
                                        {0}
                                    ) AS T(name)
                                INNER JOIN hive_accounts ha ON ha.name = T.name
                            ) AS ds (follower_id)
                            WHERE
                                hf.follower = ds.follower_id
                                AND following = (SELECT id FROM hive_accounts WHERE name = 'null')
                        """.format(query_values)
                    if sql is not None:
                        cls.beginTx()
                        DB.query(sql)
                        cls.commitTx()
                    n += len(chunk)
            cls.follow_update_items_to_flush.clear()
            cls.idx = 0
        return n

    @classmethod
    def flush(cls, trx=False):
        """Flushes pending follow count deltas."""

        n = cls._flush_follow_items()

        updated = 0
        sqls = []
        for col, deltas in cls._delta.items():
            for delta, names in _flip_dict(deltas).items():
                updated += len(names)
                query_values = ','.join(["({})".format(account) for account in names])
                sql = """
                    UPDATE
                        hive_accounts ha
                    SET
                        %s = %s + :mag
                    FROM
                    (
                        VALUES
                        %s
                    ) AS T(name)
                    WHERE ha.name = T.name
                """
                sqls.append((sql % (col, col, query_values), dict(mag=delta)))

        if not updated:
            return n

        start = perf()
        cls.db.batch_queries(sqls, trx=trx)
        if trx:
            log.info("[SYNC] flushed %d follow deltas in %ds",
                     updated, perf() - start)

        cls._delta = {FOLLOWERS: {}, FOLLOWING: {}}
        return updated + n

    @classmethod
    def flush_recount(cls):
        """Recounts follows/following counts for all queued accounts.

        This is currently not used; this approach was shown to be too
        expensive, but it's useful in case follow counts manage to get
        out of sync.
        """
        names = set([*cls._delta[FOLLOWERS].keys(),
                   *cls._delta[FOLLOWING].keys()])
        query_values = ','.join(["({})".format(account) for account in names])
        sql = """
            UPDATE
                hive_accounts ha
            SET
                followers = (SELECT COUNT(*) FROM hive_follows WHERE state = 1 AND following = ha.id),
                following = (SELECT COUNT(*) FROM hive_follows WHERE state = 1 AND follower  = ha.id)
            FROM
            (
                VALUES
                {}
            ) AS T(name)
            WHERE ha.name = T.name
        """.format(query_values)
        cls.db.query(sql)

    @classmethod
    def force_recount(cls):
        """Recounts all follows after init sync."""
        log.info("[SYNC] query follower counts")
        sql = """
            CREATE TEMPORARY TABLE following_counts AS (
                  SELECT ha.id account_id, COUNT(state) num
                    FROM hive_accounts ha
               LEFT JOIN hive_follows hf ON ha.id = hf.follower AND state = 1
                GROUP BY ha.id);
            CREATE TEMPORARY TABLE follower_counts AS (
                  SELECT ha.id account_id, COUNT(state) num
                    FROM hive_accounts ha
               LEFT JOIN hive_follows hf ON ha.id = hf.following AND state = 1
                GROUP BY ha.id);
        """
        cls.db.query(sql)

        log.info("[SYNC] update follower counts")
        sql = """
            UPDATE hive_accounts SET followers = num FROM follower_counts
             WHERE id = account_id AND followers != num;

            UPDATE hive_accounts SET following = num FROM following_counts
             WHERE id = account_id AND following != num;
        """
        cls.db.query(sql)
