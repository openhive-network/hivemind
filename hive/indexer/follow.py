
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


def chunk(lst, n):
    for i in range(0, len(lst), n):
        yield lst[i:i + n]


#  def insert_of_update(items, follower, following, op):
    #  found = False
    #  num = len(items)
    #  for (n, (itfollower, itfollowing, itop)) in enumerate(reversed(items)):
        #  if itop['action'] in [FollowAction.ResetBlacklist, FollowAction.ResetFollowingList, FollowAction.ResetMutedList, FollowAction.ResetFollowBlacklist, FollowAction.ResetFollowMutedList, FollowAction.ResetAllLists]:
            #  break
        #  if follower == itfollower and following == itfollowing:
            #  items[num-n-1] = (follower, following, op)
            #  found = True
            #  break
    #  if not found:
        #  items.append((follower, following, op))


def insert_of_update(items, follower, following, block_num):
    for (n, (itfollower, itfollowing, itblock_num)) in enumerate(items):
        if follower == itfollower and following == itfollowing:
            items[n] = (follower, following, block_num)
            break
    else:
        items.append((follower, following, block_num))


class Follow(DbAdapterHolder):
    """Handles processing of follow-related operations."""

    #  items_to_flush = []
    unique_names = set()
    follows_items_to_flush = []
    muted_items_to_flush = []
    blacklisted_items_to_flush = []
    follow_muted_items_to_flush = []
    follow_blacklisted_items_to_flush = []


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
            'follower': op['follower'],  # Removed escape_characters
            'following': [following for following in op['following']],  # Removed escape_characters
            'action': defs[what]
        }

    @classmethod
    def process_follow_op(cls, account, op_json, block_num):
        """Process an incoming follow-related operation."""

        op = cls._validate_op(account, op_json)
        if not op:
            log.warning("Invalid operation: %s", op_json)
            return

        op['block_num'] = block_num

        follower = op['follower']
        cls.unique_names.add(follower)
        action = op['action']
        if action == FollowAction.Follow:
            for following in op.get('following', []):
                insert_of_update(cls.follows_items_to_flush, follower, following, op['block_num'])
                insert_of_update(cls.muted_items_to_flush, follower, following, 0)
                cls.unique_names.add(following)
                cls.idx += 1
        elif action == FollowAction.Mute:
            for following in op.get('following', []):
                insert_of_update(cls.follows_items_to_flush, follower, following, 0)
                insert_of_update(cls.muted_items_to_flush, follower, following, op['block_num'])
                cls.unique_names.add(following)
                cls.idx += 1
        elif action == FollowAction.Nothing:
            for following in op.get('following', []):
                insert_of_update(cls.follows_items_to_flush, follower, following, 0)
                insert_of_update(cls.muted_items_to_flush, follower, following, 0)
                cls.unique_names.add(following)
                cls.idx += 1
        elif action == FollowAction.Blacklist:
            for following in op.get('following', []):
                insert_of_update(cls.blacklisted_items_to_flush, follower, following, op['block_num'])
                cls.unique_names.add(following)
                cls.idx += 1
        elif action == FollowAction.Unblacklist:
            for following in op.get('following', []):
                insert_of_update(cls.blacklisted_items_to_flush, follower, following, 0)
                cls.unique_names.add(following)
                cls.idx += 1
        elif action == FollowAction.FollowBlacklisted:
            for following in op.get('following', []):
                insert_of_update(cls.follow_blacklisted_items_to_flush, follower, following, op['block_num'])
                cls.unique_names.add(following)
                cls.idx += 1
        elif action == FollowAction.UnFollowBlacklisted:
            for following in op.get('following', []):
                insert_of_update(cls.follow_blacklisted_items_to_flush, follower, following, 0)
                cls.unique_names.add(following)
                cls.idx += 1
        elif action == FollowAction.FollowMuted:
            for following in op.get('following', []):
                insert_of_update(cls.follow_muted_items_to_flush, follower, following, op['block_num'])
                cls.unique_names.add(following)
                cls.idx += 1
        elif action == FollowAction.UnfollowMuted:
            for following in op.get('following', []):
                insert_of_update(cls.follow_muted_items_to_flush, follower, following, 0)
                cls.unique_names.add(following)
                cls.idx += 1
        elif action == FollowAction.ResetBlacklist:
            insert_of_update(cls.blacklisted_items_to_flush, follower, 0, -1)
            cls.idx += 1
        elif action == FollowAction.ResetFollowingList:
            insert_of_update(cls.follows_items_to_flush, follower, 0, -1)
            cls.idx += 1
        elif action == FollowAction.ResetMutedList:
            insert_of_update(cls.muted_items_to_flush, follower, 0, -1)
            cls.idx += 1
        elif action == FollowAction.ResetFollowBlacklist:
            insert_of_update(cls.follow_blacklisted_items_to_flush, follower, 0, -1)
            insert_of_update(cls.follow_muted_items_to_flush, follower, "null", op['block_num'])
            cls.unique_names.add("null")
            cls.idx += 1
        elif action == FollowAction.ResetFollowMutedList:
            insert_of_update(cls.follow_muted_items_to_flush, follower, 0, -1)
            insert_of_update(cls.follow_muted_items_to_flush, follower, "null", op['block_num'])
            cls.unique_names.add("null")
            cls.idx += 1
        elif action == FollowAction.ResetAllLists:
            insert_of_update(cls.blacklisted_items_to_flush, follower, 0, -1)
            insert_of_update(cls.follows_items_to_flush, follower, 0, -1)
            insert_of_update(cls.muted_items_to_flush, follower, 0, -1)
            insert_of_update(cls.follow_blacklisted_items_to_flush, follower, 0, -1)
            insert_of_update(cls.follow_muted_items_to_flush, follower, 0, -1)
            cls.idx += 1
        else:
            raise Exception(f"Invalid action {action}")

    @classmethod
    def flush(cls):
        """Flush accumulated follow operations to the database in batches."""
        n = len(cls.follows_items_to_flush) + len(cls.muted_items_to_flush) + len(cls.blacklisted_items_to_flush) + len(cls.follow_muted_items_to_flush) + len(cls.follow_blacklisted_items_to_flush)
        if n == 0:
            return 0

        cls.beginTx()

        name_to_id_records = cls.db.query_all(f"""SELECT name, id FROM {SCHEMA_NAME}.hive_accounts WHERE name IN :names""", names=tuple(cls.unique_names | set(['null'])))
        name_to_id = {record['name']: record['id'] for record in name_to_id_records}

        missing_accounts = cls.unique_names - set(name_to_id.keys())
        if missing_accounts:
            log.warning(f"Missing account IDs for names: {missing_accounts}")

        follows_items = [str((name_to_id.get(follower), name_to_id.get(following, following), block_num)) for (follower, following, block_num) in cls.follows_items_to_flush]
        muted_items = [str((name_to_id.get(follower), name_to_id.get(following, following), block_num)) for (follower, following, block_num) in cls.muted_items_to_flush]
        blacklisted_items = [str((name_to_id.get(follower), name_to_id.get(following, following), block_num)) for (follower, following, block_num) in cls.blacklisted_items_to_flush]
        follow_muted_items = [str((name_to_id.get(follower), name_to_id.get(following, following), block_num)) for (follower, following, block_num) in cls.follow_muted_items_to_flush]
        follow_blacklisted_items = [str((name_to_id.get(follower), name_to_id.get(following, following), block_num)) for (follower, following, block_num) in cls.follow_blacklisted_items_to_flush]

        for items in chunk(follows_items, 1000):
            cls.db.query_no_return(f"CALL {SCHEMA_NAME}.insert_follows(ARRAY[{','.join(items)}]::hivemind_app.follows_tuple[])")
        delete = any([block_num == 0 for (_, _, block_num) in cls.follows_items_to_flush])
        reset = any([block_num == -1 for (_, _, block_num) in cls.follows_items_to_flush])
        if delete or reset:
            cls.db.query_no_return(f"CALL {SCHEMA_NAME}.delete_follows({delete}, {reset})")

        for items in chunk(muted_items, 1000):
            cls.db.query_no_return(f"CALL {SCHEMA_NAME}.insert_muted(ARRAY[{','.join(items)}]::hivemind_app.follows_tuple[])")
        delete = any([block_num == 0 for (_, _, block_num) in cls.muted_items_to_flush])
        reset = any([block_num == -1 for (_, _, block_num) in cls.muted_items_to_flush])
        if delete or reset:
            cls.db.query_no_return(f"CALL {SCHEMA_NAME}.delete_muted({delete}, {reset})")

        for items in chunk(blacklisted_items, 1000):
            cls.db.query_no_return(f"CALL {SCHEMA_NAME}.insert_blacklisted(ARRAY[{','.join(items)}]::hivemind_app.follows_tuple[])")
        delete = any([block_num == 0 for (_, _, block_num) in cls.blacklisted_items_to_flush])
        reset = any([block_num == -1 for (_, _, block_num) in cls.blacklisted_items_to_flush])
        if delete or reset:
            cls.db.query_no_return(f"CALL {SCHEMA_NAME}.delete_blacklisted({delete}, {reset})")

        for items in chunk(follow_muted_items, 1000):
            cls.db.query_no_return(f"CALL {SCHEMA_NAME}.insert_follow_muted(ARRAY[{','.join(items)}]::hivemind_app.follows_tuple[])")
        delete = any([block_num == 0 for (_, _, block_num) in cls.follow_muted_items_to_flush])
        reset = any([block_num == -1 for (_, _, block_num) in cls.follow_muted_items_to_flush])
        if delete or reset:
            cls.db.query_no_return(f"CALL {SCHEMA_NAME}.delete_follow_muted({delete}, {reset})")

        for items in chunk(follow_blacklisted_items, 1000):
            cls.db.query_no_return(f"CALL {SCHEMA_NAME}.insert_follow_blacklisted(ARRAY[{','.join(items)}]::hivemind_app.follows_tuple[])")
        delete = any([block_num == 0 for (_, _, block_num) in cls.follow_blacklisted_items_to_flush])
        reset = any([block_num == -1 for (_, _, block_num) in cls.follow_blacklisted_items_to_flush])
        if delete or reset:
            cls.db.query_no_return(f"CALL {SCHEMA_NAME}.delete_follow_blacklisted({delete}, {reset})")

        #  cls.items_to_flush.clear()
        cls.follows_items_to_flush.clear()
        cls.muted_items_to_flush.clear()
        cls.blacklisted_items_to_flush.clear()
        cls.follow_muted_items_to_flush.clear()
        cls.follow_blacklisted_items_to_flush.clear()
        cls.unique_names.clear()
        cls.commitTx()
        return n
