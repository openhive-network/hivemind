import logging
import enum

from hive.conf import SCHEMA_NAME
from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.indexer.accounts import Accounts
from hive.utils.normalize import escape_characters
from funcy.seqs import first  # Ensure 'first' is imported

log = logging.getLogger(__name__)


class FollowAction(enum.IntEnum):
    Nothing = 0
    Mute = 1
    Blacklist = 2
    Unblacklist = 4
    Follow = 5
    FollowBlacklisted = 7  # Added for 'follow_blacklist'
    UnFollowBlacklisted = 8  # Added for 'unfollow_blacklist'
    FollowMuted = 9  # Added for 'follow_muted'
    UnfollowMuted = 10  # Added for 'unfollow_muted'
    ResetBlacklist = 11  # cancel all existing records of Blacklist type
    ResetFollowingList = 12  # cancel all existing records of Blog type
    ResetMutedList = 13  # cancel all existing records of Ignore type
    ResetFollowBlacklist = 14  # cancel all existing records of Follow_blacklist type
    ResetFollowMutedList = 15  # cancel all existing records of Follow_muted type
    ResetAllLists = 16  # cancel all existing records of all types


def insert_or_update(items, follower, following, block_num):
    for (n, (itfollower, itfollowing, itblock_num)) in enumerate(items):
        if follower == itfollower and following == itfollowing:
            items[n] = (follower, following, block_num)
            break
    else:
        items.append((follower, following, block_num))


class Batch():

    def __init__(self):
        self.data = [('', [])]

    def iter(self):
        return iter(self.data)

    def new(self, mode):
        self.data.append((mode, []))

    def mode(self):
        (mode, _) = self.data[-1]
        return mode

    def add_insert(self, follower, following, block_num):
        if self.mode() != 'insert':
            self.new('insert')
        insert_or_update(self.data[-1][1], follower, following, block_num)

    def add_delete(self, follower, following, block_num):
        if self.mode() != 'delete':
            self.new('delete')
        insert_or_update(self.data[-1][1], follower, following, block_num)

    def add_reset(self, follower, following, block_num):
        if self.mode() != 'reset':
            self.new('reset')
        insert_or_update(self.data[-1][1], follower, following, block_num)

    def len(self):
        return len(self.data)

    def clear(self):
        self.data.clear()
        self.new('')


class Follow(DbAdapterHolder):
    """Handles processing of follow-related operations."""

    follows_batches_to_flush = Batch()
    muted_batches_to_flush = Batch()
    blacklisted_batches_to_flush = Batch()
    follow_muted_batches_to_flush = Batch()
    follow_blacklisted_batches_to_flush = Batch()

    idx = 0

    @classmethod
    def _validate_op(cls, account, op):
        """Validate and normalize the follow-related operation."""
        if 'what' not in op or not isinstance(op['what'], list) or 'follower' not in op or 'following' not in op:
            log.info("follow_op %s ignored due to basic errors", op)
            return None

        what = first(op['what']) or ''
        # the empty 'what' is used to clear existing 'blog' or 'ignore' state, however it can also be used to
        defs = {
            '': FollowAction.Nothing,
            'blog': FollowAction.Follow,
            'follow': FollowAction.Follow,
            'ignore': FollowAction.Mute,
            'blacklist': FollowAction.Blacklist,
            'follow_blacklist': FollowAction.FollowBlacklisted,
            'unblacklist': FollowAction.Unblacklist,
            'unfollow_blacklist': FollowAction.UnFollowBlacklisted,
            'follow_muted': FollowAction.FollowMuted,
            'unfollow_muted': FollowAction.UnfollowMuted,
            'reset_blacklist': FollowAction.ResetBlacklist,
            'reset_following_list': FollowAction.ResetFollowingList,
            'reset_muted_list': FollowAction.ResetMutedList,
            'reset_follow_blacklist': FollowAction.ResetFollowBlacklist,
            'reset_follow_muted_list': FollowAction.ResetFollowMutedList,
            'reset_all_lists': FollowAction.ResetAllLists,
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

        return {
            'follower': escape_characters(op['follower']),
            'following': [escape_characters(following) for following in op['following']],
            'action': defs[what]
        }

    @classmethod
    def process_follow_op(cls, account, op_json, block_num):
        """Process an incoming follow-related operation."""

        op = cls._validate_op(account, op_json)
        if not op:
            log.warning("Invalid operation: %s", op_json)
            return

        follower = op['follower']
        action = op['action']
        if action == FollowAction.Nothing:
            for following in op.get('following', []):
                cls.follows_batches_to_flush.add_delete(follower, following, block_num)
                cls.muted_batches_to_flush.add_delete(follower, following, block_num)
                cls.idx += 1
        elif action == FollowAction.Follow:
            for following in op.get('following', []):
                cls.follows_batches_to_flush.add_insert(follower, following, block_num)
                cls.muted_batches_to_flush.add_delete(follower, following, block_num)
                cls.idx += 1
        elif action == FollowAction.Mute:
            for following in op.get('following', []):
                cls.muted_batches_to_flush.add_insert(follower, following, block_num)
                cls.follows_batches_to_flush.add_delete(follower, following, block_num)
                cls.idx += 1
        elif action == FollowAction.Blacklist:
            for following in op.get('following', []):
                cls.blacklisted_batches_to_flush.add_insert(follower, following, block_num)
                cls.idx += 1
        elif action == FollowAction.Unblacklist:
            for following in op.get('following', []):
                cls.blacklisted_batches_to_flush.add_delete(follower, following, block_num)
                cls.idx += 1
        elif action == FollowAction.FollowBlacklisted:
            for following in op.get('following', []):
                cls.follow_blacklisted_batches_to_flush.add_insert(follower, following, block_num)
                cls.idx += 1
        elif action == FollowAction.UnFollowBlacklisted:
            for following in op.get('following', []):
                cls.follow_blacklisted_batches_to_flush.add_delete(follower, following, block_num)
                cls.idx += 1
        elif action == FollowAction.FollowMuted:
            for following in op.get('following', []):
                cls.follow_muted_batches_to_flush.add_insert(follower, following, block_num)
                cls.idx += 1
        elif action == FollowAction.UnfollowMuted:
            for following in op.get('following', []):
                cls.follow_muted_batches_to_flush.add_delete(follower, following, block_num)
                cls.idx += 1
        elif action == FollowAction.ResetBlacklist:
            cls.blacklisted_batches_to_flush.add_reset(follower, None, block_num)
            cls.idx += 1
        elif action == FollowAction.ResetFollowingList:
            cls.follows_batches_to_flush.add_reset(follower, None, block_num)
            cls.idx += 1
        elif action == FollowAction.ResetMutedList:
            cls.muted_batches_to_flush.add_reset(follower, None, block_num)
            cls.idx += 1
        elif action == FollowAction.ResetFollowBlacklist:
            cls.follow_blacklisted_batches_to_flush.add_reset(follower, None, block_num)
            cls.follow_blacklisted_batches_to_flush.add_insert(follower, "'null'", block_num)
            cls.idx += 1
        elif action == FollowAction.ResetFollowMutedList:
            cls.follow_muted_batches_to_flush.add_reset(follower, None, block_num)
            cls.follow_muted_batches_to_flush.add_insert(follower, "'null'", block_num)
            cls.idx += 1
        elif action == FollowAction.ResetAllLists:
            cls.blacklisted_batches_to_flush.add_reset(follower, None, block_num)
            cls.follows_batches_to_flush.add_reset(follower, None, block_num)
            cls.muted_batches_to_flush.add_reset(follower, None, block_num)
            cls.follow_blacklisted_batches_to_flush.add_reset(follower, None, block_num)
            cls.follow_muted_batches_to_flush.add_reset(follower, None, block_num)
            cls.follow_blacklisted_batches_to_flush.add_insert(follower, "'null'", block_num)
            cls.follow_muted_batches_to_flush.add_insert(follower, "'null'", block_num)
            cls.idx += 1

    @classmethod
    def flush(cls):
        """Flush accumulated follow operations to the database in batches."""
        n = (
            cls.follows_batches_to_flush.len() +
            cls.muted_batches_to_flush.len() +
            cls.blacklisted_batches_to_flush.len() +
            cls.follow_muted_batches_to_flush.len() +
            cls.follow_blacklisted_batches_to_flush.len()
            )
        if n == 0:
            return 0

        cls.beginTx()

        for (mode, batch) in cls.follows_batches_to_flush.iter():
            if mode == 'insert':
                cls.db.query_no_return(
                    f"""
                    INSERT INTO {SCHEMA_NAME}.follows (follower, following, block_num)
                    SELECT r.id, g.id, v.block_num
                    FROM (
                        VALUES {', '.join(f"({follower}, {following}, {block_num})" for (follower, following, block_num) in batch)}
                    )
                    AS v(follower, following, block_num)
                    JOIN {SCHEMA_NAME}.hive_accounts AS r ON v.follower = r.name
                    JOIN {SCHEMA_NAME}.hive_accounts AS g ON v.following = g.name
                    ON CONFLICT (follower, following) DO UPDATE
                    SET block_num = EXCLUDED.block_num
                    """
                )
            elif mode == 'delete':
                cls.db.query_no_return(
                    f"""
                    DELETE FROM {SCHEMA_NAME}.follows f
                    USING {SCHEMA_NAME}.hive_accounts follower_acc,
                          {SCHEMA_NAME}.hive_accounts following_acc,
                          (VALUES {', '.join(f"({follower}, {following})" for (follower, following, _) in batch)})
                              AS v(follower_name, following_name)
                    WHERE f.follower = follower_acc.id
                      AND f.following = following_acc.id
                      AND follower_acc.name = v.follower_name
                      AND following_acc.name = v.following_name;
                    """
                )
            elif mode == 'reset':
                cls.db.query_no_return(
                    f"""
                    DELETE FROM {SCHEMA_NAME}.follows f
                    USING {SCHEMA_NAME}.hive_accounts follower_acc,
                          (VALUES {', '.join(f"({follower})" for (follower, _, _) in batch)})
                              AS v(follower_name)
                    WHERE f.follower = follower_acc.id
                      AND follower_acc.name = v.follower_name
                    """
                )

        for (mode, batch) in cls.muted_batches_to_flush.iter():
            if mode == 'insert':
                cls.db.query_no_return(
                    f"""
                    INSERT INTO {SCHEMA_NAME}.muted (follower, following, block_num)
                    SELECT r.id, g.id, v.block_num
                    FROM (
                        VALUES {', '.join(f"({follower}, {following}, {block_num})" for (follower, following, block_num) in batch)}
                    )
                    AS v(follower, following, block_num)
                    JOIN {SCHEMA_NAME}.hive_accounts AS r ON v.follower = r.name
                    JOIN {SCHEMA_NAME}.hive_accounts AS g ON v.following = g.name
                    ON CONFLICT (follower, following) DO UPDATE
                    SET block_num = EXCLUDED.block_num
                    """
                )
            elif mode == 'delete':
                cls.db.query_no_return(
                    f"""
                    DELETE FROM {SCHEMA_NAME}.muted f
                    USING {SCHEMA_NAME}.hive_accounts follower_acc,
                          {SCHEMA_NAME}.hive_accounts following_acc,
                          (VALUES {', '.join(f"({follower}, {following})" for (follower, following, _) in batch)})
                              AS v(follower_name, following_name)
                    WHERE f.follower = follower_acc.id
                      AND f.following = following_acc.id
                      AND follower_acc.name = v.follower_name
                      AND following_acc.name = v.following_name;
                    """
                )
            elif mode == 'reset':
                cls.db.query_no_return(
                    f"""
                    DELETE FROM {SCHEMA_NAME}.muted f
                    USING {SCHEMA_NAME}.hive_accounts follower_acc,
                          (VALUES {', '.join(f"({follower})" for (follower, _, _) in batch)})
                              AS v(follower_name)
                    WHERE f.follower = follower_acc.id
                      AND follower_acc.name = v.follower_name
                    """
                )

        for (mode, batch) in cls.blacklisted_batches_to_flush.iter():
            if mode == 'insert':
                cls.db.query_no_return(
                    f"""
                    INSERT INTO {SCHEMA_NAME}.blacklisted (follower, following, block_num)
                    SELECT r.id, g.id, v.block_num
                    FROM (
                        VALUES {', '.join(f"({follower}, {following}, {block_num})" for (follower, following, block_num) in batch)}
                    )
                    AS v(follower, following, block_num)
                    JOIN {SCHEMA_NAME}.hive_accounts AS r ON v.follower = r.name
                    JOIN {SCHEMA_NAME}.hive_accounts AS g ON v.following = g.name
                    ON CONFLICT (follower, following) DO UPDATE
                    SET block_num = EXCLUDED.block_num
                    """
                )
            elif mode == 'delete':
                cls.db.query_no_return(
                    f"""
                    DELETE FROM {SCHEMA_NAME}.blacklisted f
                    USING {SCHEMA_NAME}.hive_accounts follower_acc,
                          {SCHEMA_NAME}.hive_accounts following_acc,
                          (VALUES {', '.join(f"({follower}, {following})" for (follower, following, _) in batch)})
                              AS v(follower_name, following_name)
                    WHERE f.follower = follower_acc.id
                      AND f.following = following_acc.id
                      AND follower_acc.name = v.follower_name
                      AND following_acc.name = v.following_name;
                    """
                )
            elif mode == 'reset':
                cls.db.query_no_return(
                    f"""
                    DELETE FROM {SCHEMA_NAME}.blacklisted f
                    USING {SCHEMA_NAME}.hive_accounts follower_acc,
                          (VALUES {', '.join(f"({follower})" for (follower, _, _) in batch)})
                              AS v(follower_name)
                    WHERE f.follower = follower_acc.id
                      AND follower_acc.name = v.follower_name
                    """
                )

        for (mode, batch) in cls.follow_muted_batches_to_flush.iter():
            if mode == 'insert':
                cls.db.query_no_return(
                    f"""
                    INSERT INTO {SCHEMA_NAME}.follow_muted (follower, following, block_num)
                    SELECT r.id, g.id, v.block_num
                    FROM (
                        VALUES {', '.join(f"({follower}, {following}, {block_num})" for (follower, following, block_num) in batch)}
                    )
                    AS v(follower, following, block_num)
                    JOIN {SCHEMA_NAME}.hive_accounts AS r ON v.follower = r.name
                    JOIN {SCHEMA_NAME}.hive_accounts AS g ON v.following = g.name
                    ON CONFLICT (follower, following) DO UPDATE
                    SET block_num = EXCLUDED.block_num
                    """
                )
            elif mode == 'delete':
                cls.db.query_no_return(
                    f"""
                    DELETE FROM {SCHEMA_NAME}.follow_muted f
                    USING {SCHEMA_NAME}.hive_accounts follower_acc,
                          {SCHEMA_NAME}.hive_accounts following_acc,
                          (VALUES {', '.join(f"({follower}, {following})" for (follower, following, _) in batch)})
                              AS v(follower_name, following_name)
                    WHERE f.follower = follower_acc.id
                      AND f.following = following_acc.id
                      AND follower_acc.name = v.follower_name
                      AND following_acc.name = v.following_name;
                    """
                )
            elif mode == 'reset':
                cls.db.query_no_return(
                    f"""
                    DELETE FROM {SCHEMA_NAME}.follow_muted f
                    USING {SCHEMA_NAME}.hive_accounts follower_acc,
                          (VALUES {', '.join(f"({follower})" for (follower, _, _) in batch)})
                              AS v(follower_name)
                    WHERE f.follower = follower_acc.id
                      AND follower_acc.name = v.follower_name
                    """
                )

        for (mode, batch) in cls.follow_blacklisted_batches_to_flush.iter():
            if mode == 'insert':
                cls.db.query_no_return(
                    f"""
                    INSERT INTO {SCHEMA_NAME}.follow_blacklisted (follower, following, block_num)
                    SELECT r.id, g.id, v.block_num
                    FROM (
                        VALUES {', '.join(f"({follower}, {following}, {block_num})" for (follower, following, block_num) in batch)}
                    )
                    AS v(follower, following, block_num)
                    JOIN {SCHEMA_NAME}.hive_accounts AS r ON v.follower = r.name
                    JOIN {SCHEMA_NAME}.hive_accounts AS g ON v.following = g.name
                    ON CONFLICT (follower, following) DO UPDATE
                    SET block_num = EXCLUDED.block_num
                    """
                )
            elif mode == 'delete':
                cls.db.query_no_return(
                    f"""
                    DELETE FROM {SCHEMA_NAME}.follow_blacklisted f
                    USING {SCHEMA_NAME}.hive_accounts follower_acc,
                          {SCHEMA_NAME}.hive_accounts following_acc,
                          (VALUES {', '.join(f"({follower}, {following})" for (follower, following, _) in batch)})
                              AS v(follower_name, following_name)
                    WHERE f.follower = follower_acc.id
                      AND f.following = following_acc.id
                      AND follower_acc.name = v.follower_name
                      AND following_acc.name = v.following_name;
                    """
                )
            elif mode == 'reset':
                cls.db.query_no_return(
                    f"""
                    DELETE FROM {SCHEMA_NAME}.follow_blacklisted f
                    USING {SCHEMA_NAME}.hive_accounts follower_acc,
                          (VALUES {', '.join(f"({follower})" for (follower, _, _) in batch)})
                              AS v(follower_name)
                    WHERE f.follower = follower_acc.id
                      AND follower_acc.name = v.follower_name
                    """
                )

        cls.follows_batches_to_flush.clear()
        cls.muted_batches_to_flush.clear()
        cls.blacklisted_batches_to_flush.clear()
        cls.follow_muted_batches_to_flush.clear()
        cls.follow_blacklisted_batches_to_flush.clear()
        cls.commitTx()
        return n
