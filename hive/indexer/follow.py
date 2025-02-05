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


class Follow(DbAdapterHolder):
    """Handles processing of follow-related operations."""

    items_to_flush = []
    unique_names = set()

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
        if action in [FollowAction.ResetBlacklist, FollowAction.ResetFollowingList, FollowAction.ResetMutedList, FollowAction.ResetFollowBlacklist, FollowAction.ResetFollowMutedList, FollowAction.ResetAllLists]:
            cls.items_to_flush.append((follower, None, op))
            cls.idx += 1
        else:
            for following in op.get('following', []):
                cls.items_to_flush.append((follower, following, op))
                cls.unique_names.add(following)
                cls.idx += 1

    @classmethod
    def flush(cls):
        """Flush accumulated follow operations to the database in batches."""
        if not cls.items_to_flush:
            return 0

        n = len(cls.items_to_flush)

        cls.beginTx()

        name_to_id_records = cls.db.query_all(f"""SELECT name, id FROM {SCHEMA_NAME}.hive_accounts WHERE name IN :names""", names=tuple(cls.unique_names | set(['null'])))
        name_to_id = {record['name']: record['id'] for record in name_to_id_records}

        missing_accounts = cls.unique_names - set(name_to_id.keys())
        if missing_accounts:
            log.warning(f"Missing account IDs for names: {missing_accounts}")

        queries = []
        for (follower, following, op) in cls.items_to_flush:
            action = op['action']
            follower_id = name_to_id.get(follower)
            following_id = name_to_id.get(following)
            null_id = name_to_id.get('null')
            if action == FollowAction.Follow:
                if not follower_id or not following_id:
                    log.warning(f"Cannot insert follow record: missing IDs for follower '{follower}' or following '{following}'.")
                    continue
                queries.append(f"CALL {SCHEMA_NAME}.delete_muted({follower_id}, {following_id})")
                queries.append(f"CALL {SCHEMA_NAME}.insert_follows({follower_id}, {following_id}, {op['block_num']})")
            elif action == FollowAction.Mute:
                if not follower_id or not following_id:
                    log.warning(f"Cannot insert mute record: missing IDs for follower '{follower}' or following '{following}'.")
                    continue
                queries.append(f"CALL {SCHEMA_NAME}.insert_muted({follower_id}, {following_id}, {op['block_num']})")
                queries.append(f"CALL {SCHEMA_NAME}.delete_follows({follower_id}, {following_id})")
            elif action == FollowAction.Nothing:
                if not follower_id or not following_id:
                    log.warning(f"Cannot remove mute/follow record: missing IDs for follower '{follower}' or following '{following}'.")
                    continue
                queries.append(f"CALL {SCHEMA_NAME}.delete_follows({follower_id}, {following_id})")
                queries.append(f"CALL {SCHEMA_NAME}.delete_muted({follower_id}, {following_id})")
            elif action == FollowAction.Blacklist:
                if not follower_id or not following_id:
                    log.warning(f"Cannot insert blacklist record: missing IDs for follower '{follower}' or following '{following}'.")
                    continue
                queries.append(f"CALL {SCHEMA_NAME}.insert_blacklisted({follower_id}, {following_id}, {op['block_num']})")
            elif action == FollowAction.Unblacklist:
                if not follower_id or not following_id:
                    log.warning(f"Cannot delete unblacklist record: missing IDs for follower '{follower}' or following '{following}'.")
                    continue
                queries.append(f"CALL {SCHEMA_NAME}.delete_blacklisted({follower_id}, {following_id})")
            elif action == FollowAction.FollowMuted:
                if not follower_id or not following_id:
                    log.warning(f"Cannot insert follow_muted record: missing IDs for follower '{follower}' or following '{following}'.")
                    continue
                queries.append(f"CALL {SCHEMA_NAME}.insert_follow_muted({follower_id}, {following_id}, {op['block_num']})")
            elif action == FollowAction.UnfollowMuted:
                if not follower_id or not following_id:
                    log.warning(f"Cannot delete unfollow_muted record: missing IDs for follower '{follower}' or following '{following}'.")
                    continue
                queries.append(f"CALL {SCHEMA_NAME}.delete_follow_muted({follower_id}, {following_id})")
            elif action == FollowAction.FollowBlacklisted:
                if not follower_id or not following_id:
                    log.warning(f"Cannot insert follow_blacklisted record: missing IDs for follower '{follower}' or following '{following}'.")
                    continue
                queries.append(f"CALL {SCHEMA_NAME}.insert_follow_blacklisted({follower_id}, {following_id}, {op['block_num']})")
            elif action == FollowAction.UnFollowBlacklisted:
                if not follower_id or not following_id:
                    log.warning(f"Cannot delete unfollow_blacklisted record: missing IDs for follower '{follower}' or following '{following}'.")
                    continue
                queries.append(f"CALL {SCHEMA_NAME}.delete_follow_blacklisted({follower_id}, {following_id})")
            elif action == FollowAction.ResetFollowingList:
                if not follower_id:
                    log.warning("Cannot reset follow records: missing ID for follower.")
                    continue
                queries.append(f"CALL {SCHEMA_NAME}.reset_follows({follower_id})")
            elif action == FollowAction.ResetMutedList:
                if not follower_id:
                    log.warning("Cannot reset muted list records: missing ID for follower.")
                    continue
                queries.append(f"CALL {SCHEMA_NAME}.reset_muted({follower_id})")
            elif action == FollowAction.ResetBlacklist:
                if not follower_id:
                    log.warning("Cannot reset blacklist records: missing ID for follower.")
                    continue
                queries.append(f"CALL {SCHEMA_NAME}.reset_blacklisted({follower_id})")
            elif action == FollowAction.ResetFollowMutedList:
                if not follower_id:
                    log.warning("Cannot reset follow muted list records: missing ID for follower.")
                    continue
                queries.append(f"CALL {SCHEMA_NAME}.reset_follow_muted({follower_id})")
                queries.append(f"CALL {SCHEMA_NAME}.insert_follow_muted({follower_id}, {null_id}, {op['block_num']})")
            elif action == FollowAction.ResetFollowBlacklist:
                if not follower_id:
                    log.warning("Cannot reset follow blacklist records: missing ID for follower.")
                    continue
                queries.append(f"CALL {SCHEMA_NAME}.reset_follow_blacklisted({follower_id})")
                queries.append(f"CALL {SCHEMA_NAME}.insert_follow_blacklisted({follower_id}, {null_id}, {op['block_num']})")
            elif action == FollowAction.ResetAllLists:
                if not follower_id:
                    log.warning("Cannot reset all follow list records: missing ID for follower.")
                    continue
                queries.append(f"CALL {SCHEMA_NAME}.reset_blacklisted({follower_id})")
                queries.append(f"CALL {SCHEMA_NAME}.reset_follows({follower_id})")
                queries.append(f"CALL {SCHEMA_NAME}.reset_muted({follower_id})")
                queries.append(f"CALL {SCHEMA_NAME}.reset_follow_blacklisted({follower_id})")
                queries.append(f"CALL {SCHEMA_NAME}.reset_follow_muted({follower_id})")
                queries.append(f"CALL {SCHEMA_NAME}.insert_follow_muted({follower_id}, {null_id}, {op['block_num']})")
                queries.append(f"CALL {SCHEMA_NAME}.insert_follow_blacklisted({follower_id}, {null_id}, {op['block_num']})")
            else:
                raise Exception(f"Invalid action {action}")

        for q in chunk(queries, 1000):
            cls.db.query_no_return(';\n'.join(q))

        cls.items_to_flush.clear()
        cls.unique_names.clear()
        cls.commitTx()
        return n
