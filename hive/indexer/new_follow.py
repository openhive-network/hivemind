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
    Unmute = 3
    Unblacklist = 4
    Follow = 5
    Unfollow = 6
    FollowBlacklisted = 7  # Added for 'follow_blacklist'
    UnFollowBlacklisted = 8  # Added for 'unfollow_blacklist'
    FollowMuted = 9  # Added for 'follow_muted'
    UnfollowMuted = 10  # Added for 'unfollow_muted'
    # Add other actions as needed


class NewFollow(DbAdapterHolder):
    """Handles processing of new follow-related operations."""

    mute_items_to_flush = {}
    blacklisted_items_to_flush = {}
    follow_muted_items_to_flush = {}
    follow_blacklisted_items_to_flush = {}
    follow_items_to_flush = {}

    idx = 0

    @classmethod
    def _validate_op(cls, account, op):
        """Validate and normalize the new follow-related operation."""
        if 'what' not in op or not isinstance(op['what'], list) or 'follower' not in op or 'following' not in op:
            log.info("follow_op %s ignored due to basic errors", op)
            return None

        what = first(op['what']) or ''
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
            'reset_blacklist': NewFollowAction.Nothing,
            'reset_following_list': NewFollowAction.Nothing,
            'reset_muted_list': NewFollowAction.Nothing,
            'reset_follow_blacklist': NewFollowAction.Nothing,
            'reset_follow_muted_list': NewFollowAction.Nothing,
            'reset_all_lists': NewFollowAction.Nothing,
        }
        if not isinstance(what, str) or what not in defs:
            log.info("follow_op %s ignored due to unknown type of follow", op)
            return None

        if not op['follower'] or not Accounts.exists(op['follower']) or op['follower'] != account:
            log.info("follow_op %s ignored due to invalid follower", op)
            return None

        return {
            'follower': escape_characters(op['follower']),
            'following': escape_characters(op['following']),
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
        action = op['action']
        follower = op['follower']
        following = op['following']

        key = (follower, following)

        # Process the operation and accumulate in memory
        if action == NewFollowAction.Mute:
            cls.mute_items_to_flush[key] = op
        elif action == NewFollowAction.Blacklist:
            cls.blacklisted_items_to_flush[key] = op
        elif action == NewFollowAction.Unmute:
            if key in cls.mute_items_to_flush:
                del cls.mute_items_to_flush[key]
        elif action == NewFollowAction.Unblacklist:
            if key in cls.blacklisted_items_to_flush:
                del cls.blacklisted_items_to_flush[key]
        elif action == NewFollowAction.Follow:
            cls.follow_items_to_flush[key] = op
        elif action == NewFollowAction.Unfollow:
            if key in cls.follow_items_to_flush:
                del cls.follow_items_to_flush[key]
        elif action == NewFollowAction.FollowBlacklisted:
            cls.follow_blacklisted_items_to_flush[key] = op
        elif action == NewFollowAction.UnFollowBlacklisted:
            if key in cls.follow_blacklisted_items_to_flush:
                del cls.follow_blacklisted_items_to_flush[key]
        elif action == NewFollowAction.FollowMuted:
            cls.follow_muted_items_to_flush[key] = op
        elif action == NewFollowAction.UnfollowMuted:
            if key in cls.follow_muted_items_to_flush:
                del cls.follow_muted_items_to_flush[key]

        cls.idx += 1

    @classmethod
    def flush(cls):
        """Flush accumulated follow operations to the database in batches."""
        n = 0

        if cls.mute_items_to_flush or cls.blacklisted_items_to_flush or cls.follow_muted_items_to_flush or cls.follow_blacklisted_items_to_flush or cls.follow_items_to_flush:
            cls.beginTx()
            if cls.mute_items_to_flush:
                # Insert or update mute records
                for key, op in cls.mute_items_to_flush.items():
                    cls.db.query_no_return(
                        f"""
                        INSERT INTO {SCHEMA_NAME}.muted (follower, following, block_num)
                        VALUES (%s, %s, %s)
                        ON CONFLICT (follower, following) DO UPDATE
                        SET block_num = EXCLUDED.block_num
                        """,
                        (op['follower'], op['following'], op['block_num'])
                    )
                cls.mute_items_to_flush.clear()
                n += 1

            if cls.blacklisted_items_to_flush:
                # Insert or update blacklist records
                for key, op in cls.blacklisted_items_to_flush.items():
                    cls.db.query_no_return(
                        f"""
                        INSERT INTO {SCHEMA_NAME}.blacklisted (follower, following, block_num)
                        VALUES (%s, %s, %s)
                        ON CONFLICT (follower, following) DO UPDATE
                        SET block_num = EXCLUDED.block_num
                        """,
                        (op['follower'], op['following'], op['block_num'])
                    )
                cls.blacklisted_items_to_flush.clear()
                n += 1

            if cls.follow_muted_items_to_flush:
                # Insert or update follow_muted records
                for key, op in cls.follow_muted_items_to_flush.items():
                    cls.db.query_no_return(
                        f"""
                        INSERT INTO {SCHEMA_NAME}.follow_muted (follower, following, block_num)
                        VALUES (%s, %s, %s)
                        ON CONFLICT (follower, following) DO UPDATE
                        SET block_num = EXCLUDED.block_num
                        """,
                        (op['follower'], op['following'], op['block_num'])
                    )
                cls.follow_muted_items_to_flush.clear()
                n += 1

            if cls.follow_blacklisted_items_to_flush:
                # Insert or update follow_blacklist records
                for key, op in cls.follow_blacklisted_items_to_flush.items():
                    cls.db.query_no_return(
                        f"""
                        INSERT INTO {SCHEMA_NAME}.follow_blacklisted (follower, following, block_num)
                        VALUES (%s, %s, %s)
                        ON CONFLICT (follower, following) DO UPDATE
                        SET block_num = EXCLUDED.block_num
                        """,
                        (op['follower'], op['following'], op['block_num'])
                    )
                cls.follow_blacklisted_items_to_flush.clear()
                n += 1

            if cls.follow_items_to_flush:
                # Insert or update follow records
                for key, op in cls.follow_items_to_flush.items():
                    cls.db.query_no_return(
                        f"""
                        INSERT INTO {SCHEMA_NAME}.follows (follower, following, block_num)
                        VALUES (%s, %s, %s)
                        ON CONFLICT (follower, following) DO UPDATE
                        SET block_num = EXCLUDED.block_num
                        """,
                        (op['follower'], op['following'], op['block_num'])
                    )
                cls.follow_items_to_flush.clear()
                n += 1
            cls.commitTx()
        return n
