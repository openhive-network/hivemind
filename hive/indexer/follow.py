"""Handles follow operations."""

import logging
from time import perf_counter as perf

from funcy.seqs import first
from hive.db.adapter import Db
from hive.db.db_state import DbState
from hive.indexer.accounts import Accounts
from hive.indexer.notify import Notify

from hive.indexer.db_adapter_holder import DbAdapterHolder

log = logging.getLogger(__name__)

FOLLOWERS = 'followers'
FOLLOWING = 'following'

FOLLOW_ITEM_INSERT_QUERY = """
    INSERT INTO hive_follows as hf (follower, following, created_at, state, blacklisted, follow_blacklists, block_num)
    VALUES 
        (
            :flr, 
            :flg, 
            :at, 
            :state, 
            (CASE :state
                WHEN 3 THEN TRUE
                WHEN 4 THEN FALSE
                ELSE FALSE
            END
            ), 
            (CASE :state
                WHEN 3 THEN FALSE
                WHEN 4 THEN TRUE
                ELSE TRUE
            END
            ),
            :block_num
        )
    ON CONFLICT (follower, following) DO UPDATE 
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
                                END)
    """

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

    @classmethod
    def follow_op(cls, account, op_json, date, block_num):
        """Process an incoming follow op."""
        op = cls._validated_op(account, op_json, date)
        if not op:
            return
        op['block_num'] = block_num

        # perform delta check
        new_state = op['state']
        old_state = None
        if DbState.is_initial_sync():
            # insert or update state

            k = '{}/{}'.format(op['flr'], op['flg'])

            if k in cls.follow_items_to_flush:
                old_value = cls.follow_items_to_flush.get(k)
                old_value['state'] = op['state'] 
                cls.follow_items_to_flush[k] = old_value
            else:
                cls.follow_items_to_flush[k] = dict(
                                                      flr=op['flr'],
                                                      flg=op['flg'],
                                                      state=op['state'],
                                                      at=op['at'],
                                                      block_num=op['block_num'])

        else:
            old_state = cls._get_follow_db_state(op['flr'], op['flg'])
            # insert or update state
            cls.db.query(FOLLOW_ITEM_INSERT_QUERY, **op)
            if new_state == 1:
                Follow.follow(op['flr'], op['flg'])
                if old_state is None:
                    score = Accounts.default_score(op_json['follower'])
                    Notify('follow', src_id=op['flr'], dst_id=op['flg'],
                           when=op['at'], score=score).write()
            if old_state == 1:
                Follow.unfollow(op['flr'], op['flg'])

    @classmethod
    def _validated_op(cls, account, op, date):
        """Validate and normalize the operation."""
        if(not 'what' in op
           or not isinstance(op['what'], list)
           or not 'follower' in op
           or not 'following' in op):
            return None

        what = first(op['what']) or ''
        if not isinstance(what, str):
            return None
        defs = {'': 0, 'blog': 1, 'ignore': 2, 'blacklist': 3, 'follow_blacklist': 4, 'unblacklist': 5, 'unfollow_blacklist': 6}
        if what not in defs:
            return None

        if(op['follower'] == op['following']        # can't follow self
           or op['follower'] != account             # impersonation
           or not Accounts.exists(op['following'])  # invalid account
           or not Accounts.exists(op['follower'])): # invalid account
            return None

        return dict(flr=Accounts.get_id(op['follower']),
                    flg=Accounts.get_id(op['following']),
                    state=defs[what],
                    at=date)

    @classmethod
    def _get_follow_db_state(cls, follower, following):
        """Retrieve current follow state of an account pair."""
        sql = """SELECT state FROM hive_follows
                  WHERE follower = :follower
                    AND following = :following"""
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
        sql_prefix = """
              INSERT INTO hive_follows as hf (follower, following, created_at, state, blacklisted, follow_blacklists, block_num)
              VALUES """

        sql_postfix = """
              ON CONFLICT ON CONSTRAINT hive_follows_pk DO UPDATE 
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
                                        END)
              WHERE hf.following = EXCLUDED.following AND hf.follower = EXCLUDED.follower
              """
        values = []
        limit = 1000
        count = 0
        for _, follow_item in cls.follow_items_to_flush.items():
            if count < limit:
                values.append("({}, {}, '{}', {}, {}, {}, {})".format(follow_item['flr'], follow_item['flg'],
                                                                  follow_item['at'], follow_item['state'],
                                                                  follow_item['state'] == 3,
                                                                  follow_item['state'] == 4,
                                                                  follow_item['block_num']))
                count = count + 1
            else:
                query = sql_prefix + ",".join(values)
                query += sql_postfix
                cls.db.query(query)
                values.clear()
                values.append("({}, {}, '{}', {}, {}, {}, {})".format(follow_item['flr'], follow_item['flg'],
                                                                  follow_item['at'], follow_item['state'],
                                                                  follow_item['state'] == 3,
                                                                  follow_item['state'] == 4,
                                                                  follow_item['block_num']))
                count = 1

        if len(values) > 0:
            query = sql_prefix + ",".join(values)
            query += sql_postfix
            cls.db.query(query)

        cls.follow_items_to_flush.clear()

    @classmethod
    def flush(cls, trx=True):
        """Flushes pending follow count deltas."""

        cls._flush_follow_items()

        updated = 0
        sqls = []
        for col, deltas in cls._delta.items():
            for delta, names in _flip_dict(deltas).items():
                updated += len(names)
                sql = "UPDATE hive_accounts SET %s = %s + :mag WHERE id IN :ids"
                sqls.append((sql % (col, col), dict(mag=delta, ids=tuple(names))))

        if not updated:
            return 0

        start = perf()
        cls.db.batch_queries(sqls, trx=trx)
        if trx:
            log.info("[SYNC] flushed %d follow deltas in %ds",
                     updated, perf() - start)

        cls._delta = {FOLLOWERS: {}, FOLLOWING: {}}
        return updated

    @classmethod
    def flush_recount(cls):
        """Recounts follows/following counts for all queued accounts.

        This is currently not used; this approach was shown to be too
        expensive, but it's useful in case follow counts manage to get
        out of sync.
        """
        ids = set([*cls._delta[FOLLOWERS].keys(),
                   *cls._delta[FOLLOWING].keys()])
        sql = """
            UPDATE hive_accounts
               SET followers = (SELECT COUNT(*) FROM hive_follows WHERE state = 1 AND following = hive_accounts.id),
                   following = (SELECT COUNT(*) FROM hive_follows WHERE state = 1 AND follower  = hive_accounts.id)
             WHERE id IN :ids
        """
        cls.db.query(sql, ids=tuple(ids))

    @classmethod
    def force_recount(cls):
        """Recounts all follows after init sync."""
        log.info("[SYNC] query follower counts")
        sql = """
            CREATE TEMPORARY TABLE following_counts AS (
                  SELECT id account_id, COUNT(state) num
                    FROM hive_accounts
               LEFT JOIN hive_follows hf ON id = hf.follower AND state = 1
                GROUP BY id);
            CREATE TEMPORARY TABLE follower_counts AS (
                  SELECT id account_id, COUNT(state) num
                    FROM hive_accounts
               LEFT JOIN hive_follows hf ON id = hf.following AND state = 1
                GROUP BY id);
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
