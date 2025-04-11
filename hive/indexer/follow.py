import logging
import enum

from hive.conf import SCHEMA_NAME
from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.indexer.accounts import Accounts
from hive.indexer.notification_cache import NotificationCache
from hive.utils.normalize import escape_characters
from hive.utils.misc import chunks
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
        self.data = []

    def iter(self):
        return iter(self.data)

    def new(self, mode):
        self.data.append((mode, []))

    def mode(self):
        if len(self.data) > 0:
            (mode, _) = self.data[-1]
            return mode
        else:
            return ''

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


class Follow(DbAdapterHolder):
    """Handles processing of follow-related operations."""

    follows_batches_to_flush = Batch()
    muted_batches_to_flush = Batch()
    blacklisted_batches_to_flush = Batch()
    follow_muted_batches_to_flush = Batch()
    follow_blacklisted_batches_to_flush = Batch()
    affected_accounts = set()
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
        cls.affected_accounts.add(follower)
        if action == FollowAction.Nothing:
            for following in op.get('following', []):
                cls.follows_batches_to_flush.add_delete(follower, following, block_num)
                cls.muted_batches_to_flush.add_delete(follower, following, block_num)
                cls.affected_accounts.add(following)
                cls.idx += 1
        elif action == FollowAction.Follow:
            for following in op.get('following', []):
                cls.follows_batches_to_flush.add_insert(follower, following, block_num)
                cls.muted_batches_to_flush.add_delete(follower, following, block_num)
                cls.affected_accounts.add(following)
                cls.idx += 1
                NotificationCache.follow_notifications_to_flush.append((follower, following, block_num))
        elif action == FollowAction.Mute:
            for following in op.get('following', []):
                cls.muted_batches_to_flush.add_insert(follower, following, block_num)
                cls.follows_batches_to_flush.add_delete(follower, following, block_num)
                cls.affected_accounts.add(following)
                cls.idx += 1
        elif action == FollowAction.Blacklist:
            for following in op.get('following', []):
                cls.blacklisted_batches_to_flush.add_insert(follower, following, block_num)
                cls.affected_accounts.add(following)
                cls.idx += 1
        elif action == FollowAction.Unblacklist:
            for following in op.get('following', []):
                cls.blacklisted_batches_to_flush.add_delete(follower, following, block_num)
                cls.affected_accounts.add(following)
                cls.idx += 1
        elif action == FollowAction.FollowBlacklisted:
            for following in op.get('following', []):
                cls.follow_blacklisted_batches_to_flush.add_insert(follower, following, block_num)
                cls.affected_accounts.add(following)
                cls.idx += 1
        elif action == FollowAction.UnFollowBlacklisted:
            for following in op.get('following', []):
                cls.follow_blacklisted_batches_to_flush.add_delete(follower, following, block_num)
                cls.affected_accounts.add(following)
                cls.idx += 1
        elif action == FollowAction.FollowMuted:
            for following in op.get('following', []):
                cls.follow_muted_batches_to_flush.add_insert(follower, following, block_num)
                cls.affected_accounts.add(following)
                cls.idx += 1
        elif action == FollowAction.UnfollowMuted:
            for following in op.get('following', []):
                cls.follow_muted_batches_to_flush.add_delete(follower, following, block_num)
                cls.affected_accounts.add(following)
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
            cls.idx += 1
        elif action == FollowAction.ResetFollowMutedList:
            cls.follow_muted_batches_to_flush.add_reset(follower, None, block_num)
            cls.idx += 1
        elif action == FollowAction.ResetAllLists:
            cls.blacklisted_batches_to_flush.add_reset(follower, None, block_num)
            cls.follows_batches_to_flush.add_reset(follower, None, block_num)
            cls.muted_batches_to_flush.add_reset(follower, None, block_num)
            cls.follow_blacklisted_batches_to_flush.add_reset(follower, None, block_num)
            cls.follow_muted_batches_to_flush.add_reset(follower, None, block_num)
            cls.idx += 1

    @classmethod
    def flush_follows(cls):
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

        follows = []
        muted = []
        blacklisted = []
        follow_muted = []
        follow_blacklisted = []
        for (n, (mode, batch)) in enumerate(cls.follows_batches_to_flush.iter()):
            follows.append(f"""({n}, '{mode}', array[{','.join([f"({r},{g or 'NULL'},{b})::hivemind_app.follow" for r,g,b in batch])}])::hivemind_app.follow_updates""")
        for (n, (mode, batch)) in enumerate(cls.muted_batches_to_flush.iter()):
            muted.append(f"""({n}, '{mode}', array[{','.join([f"({r},{g or 'NULL'},{b})::hivemind_app.mute" for r,g,b in batch])}])::hivemind_app.mute_updates""")
        for (n, (mode, batch)) in enumerate(cls.blacklisted_batches_to_flush.iter()):
            blacklisted.append(f"""({n}, '{mode}', array[{','.join([f"({r},{g or 'NULL'},{b})::hivemind_app.blacklist" for r,g,b in batch])}])::hivemind_app.blacklist_updates""")
        for (n, (mode, batch)) in enumerate(cls.follow_muted_batches_to_flush.iter()):
            follow_muted.append(f"""({n}, '{mode}', array[{','.join([f"({r},{g or 'NULL'},{b})::hivemind_app.follow_mute" for r,g,b in batch])}])::hivemind_app.follow_mute_updates""")
        for (n, (mode, batch)) in enumerate(cls.follow_blacklisted_batches_to_flush.iter()):
            follow_blacklisted.append(f"""({n}, '{mode}', array[{','.join([f"({r},{g or 'NULL'},{b})::hivemind_app.follow_blacklist" for r,g,b in batch])}])::hivemind_app.follow_blacklist_updates""")
        if follows or muted or blacklisted or follow_muted or follow_blacklisted:
            cls.db.query_no_return(
                f"""
                CALL hivemind_app.flush_follows(
                    array[{','.join(follows)}]::hivemind_app.follow_updates[],
                    array[{','.join(muted)}]::hivemind_app.mute_updates[],
                    array[{','.join(blacklisted)}]::hivemind_app.blacklist_updates[],
                    array[{','.join(follow_muted)}]::hivemind_app.follow_mute_updates[],
                    array[{','.join(follow_blacklisted)}]::hivemind_app.follow_blacklist_updates[],
                    array[{','.join(cls.affected_accounts)}]
                    )
                """
            )

        cls.affected_accounts.clear()
        cls.follows_batches_to_flush.clear()
        cls.muted_batches_to_flush.clear()
        cls.blacklisted_batches_to_flush.clear()
        cls.follow_muted_batches_to_flush.clear()
        cls.follow_blacklisted_batches_to_flush.clear()
        cls.commitTx()
        return n

    @classmethod
    def flush(cls):
        return cls.flush_follows() + NotificationCache.flush_follow_notifications(cls)
