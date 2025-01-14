import logging
import enum

from hive.conf import SCHEMA_NAME
from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.indexer.accounts import Accounts
from hive.utils.normalize import escape_characters
from funcy.seqs import first  # Ensure 'first' is imported

log = logging.getLogger(__name__)


class NewFollowAction(enum.IntEnum):
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


class NewFollow(DbAdapterHolder):
    """Handles processing of new follow-related operations."""

    items_to_flush = []
    unique_names = set()
    nothing_items_to_flush = {}
    blacklisted_items_to_flush = {}
    follow_muted_items_to_flush = {}
    follow_blacklisted_items_to_flush = {}
    unblacklist_items_to_flush = {}
    unfollow_blacklisted_items_to_flush = {}
    unfollow_muted_items_to_flush = {}
    reset_blacklists_to_flush = {}
    reset_followinglists_to_flush = {}
    reset_mutedlists_to_flush = {}
    reset_follow_blacklists_to_flush = {}
    reset_follow_mutedlists_to_flush = {}
    reset_all_lists_to_flush = {}

    idx = 0

    @classmethod
    def _validate_op(cls, account, op):
        """Validate and normalize the new follow-related operation."""
        if 'what' not in op or not isinstance(op['what'], list) or 'follower' not in op or 'following' not in op:
            log.info("follow_op %s ignored due to basic errors", op)
            return None

        what = first(op['what']) or ''
        # the empty 'what' is used to clear existing 'blog' or 'ignore' state, however it can also be used to
        defs = {
            '': NewFollowAction.Nothing,
            'blog': NewFollowAction.Follow,
            'follow': NewFollowAction.Follow,
            'ignore': NewFollowAction.Mute,
            'blacklist': NewFollowAction.Blacklist,
            'follow_blacklist': NewFollowAction.FollowBlacklisted,
            'unblacklist': NewFollowAction.Unblacklist,
            'unfollow_blacklist': NewFollowAction.UnFollowBlacklisted,
            'follow_muted': NewFollowAction.FollowMuted,
            'unfollow_muted': NewFollowAction.UnfollowMuted,
            'reset_blacklist': NewFollowAction.ResetBlacklist,
            'reset_following_list': NewFollowAction.ResetFollowingList,
            'reset_muted_list': NewFollowAction.ResetMutedList,
            'reset_follow_blacklist': NewFollowAction.ResetFollowBlacklist,
            'reset_follow_muted_list': NewFollowAction.ResetFollowMutedList,
            'reset_all_lists': NewFollowAction.ResetAllLists,
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
    def process_new_follow_op(cls, account, op_json, block_num):
        """Process an incoming new follow-related operation."""

        op = cls._validate_op(account, op_json)
        if not op:
            log.warning("Invalid operation: %s", op_json)
            return

        op['block_num'] = block_num

        follower = op['follower']
        cls.unique_names.add(follower)
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

        name_to_id_records = cls.db.query_all(f"""SELECT name, id FROM {SCHEMA_NAME}.hive_accounts WHERE name IN :names""", names=tuple(cls.unique_names))
        name_to_id = {record['name']: record['id'] for record in name_to_id_records}

        missing_accounts = cls.unique_names - set(name_to_id.keys())
        if missing_accounts:
            log.warning(f"Missing account IDs for names: {missing_accounts}")

        for (follower, following, op) in cls.items_to_flush:
            action = op['action']
            follower_id = name_to_id.get(follower)
            following_id = name_to_id.get(following)
            match action:
                case NewFollowAction.Follow:
                    if not follower_id or not following_id:
                        log.warning(f"Cannot insert follow record: missing IDs for follower '{follower}' or following '{following}'.")
                        continue
                    cls.db.query_no_return(
                        f"""
                        DELETE FROM {SCHEMA_NAME}.muted
                        WHERE follower = :follower_id AND following = :following_id
                        """,
                        follower_id=follower_id,
                        following_id=following_id
                    )
                    cls.db.query_no_return(
                        f"""
                        INSERT INTO {SCHEMA_NAME}.follows (follower, following, block_num)
                        VALUES (:follower_id, :following_id, :block_num)
                        ON CONFLICT (follower, following) DO UPDATE
                        SET block_num = EXCLUDED.block_num
                        """,
                        follower_id=follower_id,
                        following_id=following_id,
                        block_num=op['block_num']
                    )
                case NewFollowAction.Mute:
                    if not follower_id or not following_id:
                        log.warning(f"Cannot insert mute record: missing IDs for follower '{follower}' or following '{following}'.")
                        continue
                    cls.db.query_no_return(
                        f"""
                        INSERT INTO {SCHEMA_NAME}.muted (follower, following, block_num)
                        VALUES (:follower_id, :following_id, :block_num)
                        ON CONFLICT (follower, following) DO UPDATE
                        SET block_num = EXCLUDED.block_num
                        """,
                        follower_id=follower_id,
                        following_id=following_id,
                        block_num=op['block_num']
                    )
                    cls.db.query_no_return(
                        f"""
                        DELETE FROM {SCHEMA_NAME}.follows
                        WHERE follower = :follower_id AND following = :following_id
                        """,
                        follower_id=follower_id,
                        following_id=following_id
                    )
                case NewFollowAction.Nothing:
                    if not follower_id or not following_id:
                        log.warning(f"Cannot remove mute/follow record: missing IDs for follower '{follower}' or following '{following}'.")
                        continue
                    cls.db.query_no_return(
                        f"""
                        DELETE FROM {SCHEMA_NAME}.follows
                        WHERE follower = :follower_id AND following = :following_id
                        """,
                        follower_id=follower_id,
                        following_id=following_id
                    )
                    cls.db.query_no_return(
                        f"""
                        DELETE FROM {SCHEMA_NAME}.muted
                        WHERE follower = :follower_id AND following = :following_id
                        """,
                        follower_id=follower_id,
                        following_id=following_id
                    )
                case NewFollowAction.Blacklist:
                    if not follower_id or not following_id:
                        log.warning(f"Cannot insert blacklist record: missing IDs for follower '{follower}' or following '{following}'.")
                        continue
                    cls.db.query_no_return(
                        f"""
                        INSERT INTO {SCHEMA_NAME}.blacklisted (follower, following, block_num)
                        VALUES (:follower_id, :following_id, :block_num)
                        ON CONFLICT (follower, following) DO UPDATE
                        SET block_num = EXCLUDED.block_num
                        """,
                        follower_id=follower_id,
                        following_id=following_id,
                        block_num=op['block_num']
                    )
                case NewFollowAction.Unblacklist:
                    if not follower_id or not following_id:
                        log.warning(f"Cannot delete unblacklist record: missing IDs for follower '{follower}' or following '{following}'.")
                        continue
                    cls.db.query_no_return(
                        f"""
                        DELETE FROM {SCHEMA_NAME}.blacklisted
                        WHERE follower = :follower_id AND following = :following_id
                        """,
                        follower_id=follower_id,
                        following_id=following_id
                    )

                case NewFollowAction.FollowMuted:
                    if not follower_id or not following_id:
                        log.warning(f"Cannot insert follow_muted record: missing IDs for follower '{follower}' or following '{following}'.")
                        continue

                    cls.db.query_no_return(
                        f"""
                        INSERT INTO {SCHEMA_NAME}.follow_muted (follower, following, block_num)
                        VALUES (:follower_id, :following_id, :block_num)
                        ON CONFLICT (follower, following) DO UPDATE
                        SET block_num = EXCLUDED.block_num
                        """,
                        follower_id=follower_id,
                        following_id=following_id,
                        block_num=op['block_num']
                    )
                case NewFollowAction.UnfollowMuted:
                    if not follower_id or not following_id:
                        log.warning(f"Cannot delete unfollow_muted record: missing IDs for follower '{follower}' or following '{following}'.")
                        continue

                    cls.db.query_no_return(
                        f"""
                        DELETE FROM {SCHEMA_NAME}.follow_muted
                        WHERE follower = :follower_id AND following = :following_id
                        """,
                        follower_id=follower_id,
                        following_id=following_id
                    )

                case NewFollowAction.FollowBlacklisted:
                    if not follower_id or not following_id:
                        log.warning(f"Cannot insert follow_blacklisted record: missing IDs for follower '{follower}' or following '{following}'.")
                        continue
                    cls.db.query_no_return(
                        f"""
                        INSERT INTO {SCHEMA_NAME}.follow_blacklisted (follower, following, block_num)
                        VALUES (:follower_id, :following_id, :block_num)
                        ON CONFLICT (follower, following) DO UPDATE
                        SET block_num = EXCLUDED.block_num
                        """,
                        follower_id=follower_id,
                        following_id=following_id,
                        block_num=op['block_num']
                    )
                case NewFollowAction.UnFollowBlacklisted:
                    if not follower_id or not following_id:
                        log.warning(f"Cannot delete unfollow_blacklisted record: missing IDs for follower '{follower}' or following '{following}'.")
                        continue
                    cls.db.query_no_return(
                        f"""
                        DELETE FROM {SCHEMA_NAME}.follow_blacklisted
                        WHERE follower = :follower_id AND following = :following_id
                        """,
                        follower_id=follower_id,
                        following_id=following_id
                    )

                case NewFollowAction.ResetFollowingList:
                    if not follower_id:
                        log.warning("Cannot reset follow records: missing ID for follower.")
                        continue
                    cls.db.query_no_return(
                        f"""
                        DELETE FROM {SCHEMA_NAME}.follows
                        WHERE follower=:follower_id
                        """,
                        follower_id=follower_id
                    )
                case NewFollowAction.ResetMutedList:
                    if not follower_id:
                        log.warning("Cannot reset muted list records: missing ID for follower.")
                        continue
                    cls.db.query_no_return(
                        f"""
                        DELETE FROM {SCHEMA_NAME}.muted
                        WHERE follower=:follower_id
                        """,
                        follower_id=follower_id
                    )
                case NewFollowAction.ResetBlacklist:
                    if not follower_id:
                        log.warning("Cannot reset blacklist records: missing ID for follower.")
                        continue
                    cls.db.query_no_return(
                        f"""
                        DELETE FROM {SCHEMA_NAME}.blacklisted
                        WHERE follower=:follower_id
                        """,
                        follower_id=follower_id
                    )
                case NewFollowAction.ResetFollowMutedList:
                    if not follower_id:
                        log.warning("Cannot reset follow muted list records: missing ID for follower.")
                        continue
                    cls.db.query_no_return(
                        f"""
                        DELETE FROM {SCHEMA_NAME}.follow_muted
                        WHERE follower=:follower_id
                        """,
                        follower_id=follower_id
                    )
                case NewFollowAction.ResetFollowBlacklist:
                    if not follower_id:
                        log.warning("Cannot reset follow blacklist records: missing ID for follower.")
                        continue
                    cls.db.query_no_return(
                        f"""
                        DELETE FROM {SCHEMA_NAME}.follow_blacklisted
                        WHERE follower=:follower_id
                        """,
                        follower_id=follower_id
                    )
                case NewFollowAction.ResetAllLists:
                    if not follower_id:
                        log.warning("Cannot reset all follow list records: missing ID for follower.")
                        continue
                    cls.db.query_no_return(
                        f"""
                        DELETE FROM {SCHEMA_NAME}.blacklisted
                        WHERE follower=:follower_id
                        """,
                        follower_id=follower_id
                    )
                    cls.db.query_no_return(
                        f"""
                        DELETE FROM {SCHEMA_NAME}.follows
                        WHERE follower=:follower_id
                        """,
                        follower_id=follower_id
                    )
                    cls.db.query_no_return(
                        f"""
                        DELETE FROM {SCHEMA_NAME}.muted
                        WHERE follower=:follower_id
                        """,
                        follower_id=follower_id
                    )
                    cls.db.query_no_return(
                        f"""
                        DELETE FROM {SCHEMA_NAME}.follow_blacklisted
                        WHERE follower=:follower_id
                        """,
                        follower_id=follower_id
                    )
                    cls.db.query_no_return(
                        f"""
                        DELETE FROM {SCHEMA_NAME}.follow_muted
                        WHERE follower=:follower_id
                        """,
                        follower_id=follower_id
                    )

                case _:
                    raise Exception(f"Invalid item {item}")

        cls.items_to_flush.clear()
        cls.unique_names.clear()
        cls.commitTx()
        return n
