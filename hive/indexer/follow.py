"""Handles follow operations."""

import enum
import logging

from funcy.seqs import first

from hive.conf import SCHEMA_NAME
from hive.indexer.accounts import Accounts
from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.utils.normalize import escape_characters

log = logging.getLogger(__name__)


class Action(enum.IntEnum):
    Nothing = 0  # cancel existing Blog/Ignore
    Blog = 1  # follow
    Ignore = 2  # mute
    Blacklist = 3
    Follow_blacklist = 4
    Unblacklist = 5  # cancel existing Blacklist
    Unfollow_blacklist = 6  # cancel existing Follow_blacklist
    Follow_muted = 7
    Unfollow_muted = 8  # cancel existing Follow_muted
    Reset_blacklist = 9  # cancel all existing records of Blacklist type
    Reset_following_list = 10  # cancel all existing records of Blog type
    Reset_muted_list = 11  # cancel all existing records of Ignore type
    Reset_follow_blacklist = 12  # cancel all existing records of Follow_blacklist type
    Reset_follow_muted_list = 13  # cancel all existing records of Follow_muted type
    Reset_all_lists = 14  # cancel all existing records of ??? types


class Follow(DbAdapterHolder):
    """Handles processing of incoming follow ups and flushing to db."""

    follow_items_to_flush = dict()
    list_resets_to_flush = []

    idx = 0

    @classmethod
    def _reset_blacklist(cls, data, op):
        data['idx'] = cls.idx
        data['blacklisted'] = False
        data['block_num'] = op['block_num']

    @classmethod
    def _reset_following_list(cls, data, op):
        if data['state'] == 1:
            data['idx'] = cls.idx
            data['state'] = 0
            data['block_num'] = op['block_num']

    @classmethod
    def _reset_muted_list(cls, data, op):
        if data['state'] == 2:
            data['idx'] = cls.idx
            data['state'] = 0
            data['block_num'] = op['block_num']

    @classmethod
    def _reset_follow_blacklist(cls, data, op):
        data['idx'] = cls.idx
        data['follow_blacklists'] = False
        data['block_num'] = op['block_num']

    @classmethod
    def _reset_follow_muted_list(cls, data, op):
        data['idx'] = cls.idx
        data['follow_muted'] = False
        data['block_num'] = op['block_num']

    @classmethod
    def _reset_all_lists(cls, data, op):
        data['idx'] = cls.idx
        data['state'] = 0
        data['blacklisted'] = False
        data['follow_blacklists'] = False
        data['follow_muted'] = False
        data['block_num'] = op['block_num']

    @classmethod
    def _follow_single(
        cls,
        follower,
        following,
        at,
        block_num,
        new_state=None,
        new_blacklisted=None,
        new_follow_blacklists=None,
        new_follow_muted=None,
    ):
        # add or update single record in flush cache
        k = f'{follower}/{following}'
        if k not in cls.follow_items_to_flush:
            # fresh follow item (note that db might have that pair already)
            cls.follow_items_to_flush[k] = dict(
                idx=cls.idx,
                follower=follower,
                following=following,
                state=new_state if new_state is not None else 'NULL',
                blacklisted=new_blacklisted if new_blacklisted is not None else 'NULL',
                follow_blacklists=new_follow_blacklists if new_follow_blacklists is not None else 'NULL',
                follow_muted=new_follow_muted if new_follow_muted is not None else 'NULL',
                at=at,
                block_num=block_num,
            )
        else:
            # follow item already in cache - just overwrite previous value where applicable
            cls.follow_items_to_flush[k]['idx'] = cls.idx
            if new_state is not None:
                cls.follow_items_to_flush[k]['state'] = new_state
            if new_blacklisted is not None:
                cls.follow_items_to_flush[k]['blacklisted'] = new_blacklisted
            if new_follow_blacklists is not None:
                cls.follow_items_to_flush[k]['follow_blacklists'] = new_follow_blacklists
            if new_follow_muted is not None:
                cls.follow_items_to_flush[k]['follow_muted'] = new_follow_muted
            # ABW: at not updated for some reason - will therefore always point at time of first relation between accounts
            cls.follow_items_to_flush[k]['block_num'] = block_num
        cls.idx += 1

    @classmethod
    def follow_op(cls, account, op_json, date, block_num):
        """Process an incoming follow op."""

        def true_false_none(state, to_true, to_false):
            if state == to_true:
                return True
            if state == to_false:
                return False
            return None

        op = cls._validated_op(account, op_json, date)
        if not op:
            return
        op['block_num'] = block_num
        state = int(op['state'])
        follower = op['follower']
        # log.info("follow_op accepted as %s", op)

        if state >= Action.Reset_blacklist:
            # choose action specific to requested list resetting
            add_null_blacklist = False
            add_null_muted = False
            if state == Action.Reset_blacklist:
                reset_list = Follow._reset_blacklist
                cls.list_resets_to_flush.append(
                    dict(follower=follower, reset_call='follow_reset_blacklist', block_num=block_num)
                )
            elif state == Action.Reset_following_list:
                reset_list = Follow._reset_following_list
                cls.list_resets_to_flush.append(
                    dict(follower=follower, reset_call='follow_reset_following_list', block_num=block_num)
                )
            elif state == Action.Reset_muted_list:
                reset_list = Follow._reset_muted_list
                cls.list_resets_to_flush.append(
                    dict(follower=follower, reset_call='follow_reset_muted_list', block_num=block_num)
                )
            elif state == Action.Reset_follow_blacklist:
                reset_list = Follow._reset_follow_blacklist
                cls.list_resets_to_flush.append(
                    dict(follower=follower, reset_call='follow_reset_follow_blacklist', block_num=block_num)
                )
                add_null_blacklist = True
            elif state == Action.Reset_follow_muted_list:
                reset_list = Follow._reset_follow_muted_list
                cls.list_resets_to_flush.append(
                    dict(follower=follower, reset_call='follow_reset_follow_muted_list', block_num=block_num)
                )
                add_null_muted = True
            elif state == Action.Reset_all_lists:
                reset_list = Follow._reset_all_lists
                cls.list_resets_to_flush.append(
                    dict(follower=follower, reset_call='follow_reset_all_lists', block_num=block_num)
                )
                add_null_blacklist = True
                add_null_muted = True
            else:
                assert False, 'Unhandled follow state'
            # apply action to existing cached data as well as to database (ABW: with expected frequency of list resetting
            # there is no point in grouping such operations from group of blocks - we can just execute them one by one
            # in order of appearance)
            for k, data in cls.follow_items_to_flush.items():
                if data['follower'] == follower:
                    reset_list(data, op)
            if add_null_blacklist or add_null_muted:
                # since 'null' account can't have its blacklist/mute list, following such list is only used
                # as an indicator for frontend to no longer bother user with proposition of following predefined
                # lists (since that user is already choosing his own lists)
                cls._follow_single(
                    follower,
                    escape_characters('null'),
                    op['at'],
                    op['block_num'],
                    None,
                    None,
                    add_null_blacklist,
                    add_null_muted,
                )
        else:
            # set new state/flags to be applied to each pair with changing 'following'
            new_state = state if state in (Action.Nothing, Action.Blog, Action.Ignore) else None
            new_blacklisted = true_false_none(state, Action.Blacklist, Action.Unblacklist)
            new_follow_blacklists = true_false_none(state, Action.Follow_blacklist, Action.Unfollow_blacklist)
            new_follow_muted = true_false_none(state, Action.Follow_muted, Action.Unfollow_muted)

            for following in op['following']:
                cls._follow_single(
                    follower,
                    following,
                    op['at'],
                    block_num,
                    new_state,
                    new_blacklisted,
                    new_follow_blacklists,
                    new_follow_muted,
                )

    @classmethod
    def _validated_op(cls, account, op, date):
        """Validate and normalize the operation."""
        if not 'what' in op or not isinstance(op['what'], list) or not 'follower' in op or not 'following' in op:
            log.info("follow_op %s ignored due to basic errors", op)
            return None

        what = first(op['what']) or ''
        # ABW: the empty 'what' is used to clear existing 'blog' or 'ignore' state, however it can also be used to
        # introduce new empty relation record in hive_follows adding unnecessary data (it might become a problem
        # only if we wanted to immediately remove empty records)
        # we could add aliases for '' - 'unfollow' and 'unignore'/'unmute'
        # we could add alias for 'ignore' - 'mute'
        defs = {
            '': Action.Nothing,
            'blog': Action.Blog,
            'follow': Action.Blog,
            'ignore': Action.Ignore,
            'blacklist': Action.Blacklist,
            'follow_blacklist': Action.Follow_blacklist,
            'unblacklist': Action.Unblacklist,
            'unfollow_blacklist': Action.Unfollow_blacklist,
            'follow_muted': Action.Follow_muted,
            'unfollow_muted': Action.Unfollow_muted,
            'reset_blacklist': Action.Reset_blacklist,
            'reset_following_list': Action.Reset_following_list,
            'reset_muted_list': Action.Reset_muted_list,
            'reset_follow_blacklist': Action.Reset_follow_blacklist,
            'reset_follow_muted_list': Action.Reset_follow_muted_list,
            'reset_all_lists': Action.Reset_all_lists,
        }
        if not isinstance(what, str) or what not in defs:
            log.info("follow_op %s ignored due to unknown type of follow", op)
            return None

        # follower is empty or follower account does not exist, or it wasn't that account that authorized operation
        if not op['follower'] or not Accounts.exists(op['follower']) or op['follower'] != account:
            log.info("follow_op %s ignored due to invalid follower", op)
            return None

        # normalize following to list
        op['following'] = op['following'] if isinstance(op['following'], list) else [op['following']]

        # if following name does not exist do not process it: basically equal to drop op for single following entry
        op['following'] = [
            following
            for following in op['following']
            if following and Accounts.exists(following) and following != op['follower']
        ]
        # ABW: note that since you could make 'following' list empty anyway by supplying nonexisting account
        # there was no point in excluding follow_op with provided empty list/empty string - such call actually
        # makes sense for state > 8 when 'following' is ignored
        state = defs[what]
        if not op['following'] and state < Action.Reset_blacklist:
            log.info("follow_op %s is void due to effectively empty list of following", op)
            return None

        return dict(
            follower=escape_characters(op['follower']),
            following=[escape_characters(following) for following in op['following']],
            state=state,
            at=date,
        )

    @classmethod
    def flush(cls):
        n = 0
        if cls.follow_items_to_flush or cls.list_resets_to_flush:
            cls.beginTx()

            for reset_list in cls.list_resets_to_flush:
                sql = f"SELECT {SCHEMA_NAME}.{reset_list['reset_call']}({reset_list['follower']}::VARCHAR, {reset_list['block_num']}::INT)"
                cls.db.query_no_return(sql)

            cls.list_resets_to_flush.clear()

            sql = f"""
                INSERT INTO {SCHEMA_NAME}.hive_follows as hf (follower, following, created_at, state, blacklisted, follow_blacklists, follow_muted, block_num)
                SELECT
                    ds.follower_id,
                    ds.following_id,
                    ds.created_at,
                    COALESCE(ds.state, hfs.state, 0),
                    COALESCE(ds.blacklisted, hfs.blacklisted, FALSE),
                    COALESCE(ds.follow_blacklists, hfs.follow_blacklists, FALSE),
                    COALESCE(ds.follow_muted, hfs.follow_muted, FALSE),
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
                            {{}}
                        ) as T (id, follower, following, created_at, state, blacklisted, follow_blacklists, follow_muted, block_num)
                    INNER JOIN {SCHEMA_NAME}.hive_accounts ha_flr ON ha_flr.name = T.follower
                    INNER JOIN {SCHEMA_NAME}.hive_accounts ha_flg ON ha_flg.name = T.following
                ) AS ds(id, follower_id, following_id, created_at, state, blacklisted, follow_blacklists, follow_muted, block_num)
                LEFT JOIN {SCHEMA_NAME}.hive_follows hfs ON hfs.follower = ds.follower_id AND hfs.following = ds.following_id
                ORDER BY ds.id ASC 
                ON CONFLICT ON CONSTRAINT hive_follows_ux1 DO UPDATE
                    SET
                        state = EXCLUDED.state,
                        blacklisted = EXCLUDED.blacklisted,
                        follow_blacklists = EXCLUDED.follow_blacklists,
                        follow_muted = EXCLUDED.follow_muted,
                        block_num = EXCLUDED.block_num
                WHERE hf.following = EXCLUDED.following AND hf.follower = EXCLUDED.follower
                """
            values = []
            limit = 1000
            count = 0

            for _, follow_item in cls.follow_items_to_flush.items():
                values.append(
                    f"({follow_item['idx']}, {follow_item['follower']}, {follow_item['following']}, '{follow_item['at']}'::timestamp, {follow_item['state']}::smallint, {follow_item['blacklisted']}::boolean, {follow_item['follow_blacklists']}::boolean, {follow_item['follow_muted']}::boolean, {follow_item['block_num']})"
                )
                count = count + 1
                if count >= limit:
                    query = str(sql).format(",".join(values))
                    cls.db.query_prepared(query)
                    values.clear()
                    count = 0
                n += 1

            if len(values) > 0:
                query = str(sql).format(",".join(values))
                cls.db.query_prepared(query)
                values.clear()

            cls.follow_items_to_flush.clear()

            cls.commitTx()
            cls.idx = 0
        return n
