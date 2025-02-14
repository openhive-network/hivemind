import logging
from enum import Enum, IntEnum, auto
import time
import sys
from collections import defaultdict

from hive.conf import SCHEMA_NAME
from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.indexer.accounts import Accounts
from hive.utils.normalize import escape_characters
from funcy.seqs import first  # Ensure 'first' is imported

log = logging.getLogger(__name__)


class FollowAction(IntEnum):
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


# Define enums for net operations and flush modes
class NetOp(IntEnum):
    INSERT = auto()   # first-ever follow in the chunk for this pair
    UPSERT = auto()   # a follow that comes after an unfollow (so we update block_num)
    DELETE = auto()   # net effect is unfollow

class FlushMode(IntEnum):
    INSERT = auto()  # for follow events (net INSERT or UPSERT)
    DELETE = auto()  # for unfollow events
    RESET  = auto()  # for resets (delete all for a given follower)

class NetEffectTracker:
    def __init__(self, table, track_deltas=False):
        """
        Parameters:
          schema: string, the database schema name.
          table: string, the table name.
          track_deltas: if True, flush() will return aggregated delta info
                        as a dictionary mapping account => (delta_followers, delta_following).
        """
        self.table = table
        self.track_deltas = track_deltas
        # current events per (follower, following)
        # For each key (follower, following), value is (NetOp, block_num)
        # For DELETE events, block_num is None.
        self.current = {}
        # groups: list of (FlushMode, entries)
        # For INSERT groups, entries are tuples (follower, following, block_num, NetOp)
        # For DELETE groups, entries are tuples (follower, following, None, NetOp.DELETE)
        # For RESET groups, entries are tuples (follower, block_num)
        self.groups = []

    # --- Public API: add_insert, add_delete, add_reset ---
    def add_insert(self, follower, following, block_num):
        """
        Record a follow event.
        If no prior event was recorded, assume net effect = INSERT.
        If a DELETE (unfollow) was previously recorded, then a new follow is
        treated as an UPSERT.
        """
        key = (follower, following)
        # new, believed good code
        #if key not in self.current:
        #    self.current[key] = (NetOp.INSERT, block_num)
        #else:
        #    current_op, current_blk = self.current[key]
        #    if current_op in (NetOp.INSERT, NetOp.UPSERT):
        #        # Already in a following state; ignore duplicate follow.
        #        return
        #    elif current_op == NetOp.DELETE:
        #        self.current[key] = (NetOp.UPSERT, block_num)

        # attempting to replicate old block numbering behavior
        self.current[key] = (NetOp.UPSERT, block_num)

    def add_delete(self, follower, following, block_num=None):
        """
        Record an unfollow event.
        """
        key = (follower, following)
        # (block_num is ignored for deletes)
        self.current[key] = (NetOp.DELETE, None)

    def add_reset(self, follower, dummy_block_num):
        """
        Record a reset event for the given follower.
        When a reset is encountered, we discard any pending events for that follower
        (since they will be overridden) and then record the reset as its own group.
        The dummy_block_num is provided for logging or delta purposes.
        """
        # Discard any pending events for this follower.
        keys_to_discard = [key for key in self.current if key[0] == follower]
        for key in keys_to_discard:
            del self.current[key]
        # Record the reset event.
        self.groups.append((FlushMode.RESET, [(follower, dummy_block_num)]))

    # --- Internal: Aggregate deltas ---
    def _aggregate_deltas(self, delta_list):
        """
        delta_list is a list of tuples (user, delta_followers, delta_following)
        Returns a dictionary mapping user => (delta_followers, delta_following)
        aggregated.
        """
        agg = defaultdict(lambda: [0, 0])
        for user, d_followers, d_following in delta_list:
            agg[user][0] += d_followers
            agg[user][1] += d_following
        # Convert to normal dict with tuples.
        return {user: (d[0], d[1]) for user, d in agg.items()}

    # --- Internal: Flush one group ---
    def _flush_group(self, db, mode, entries):
        """
        Flush one group (of type mode) to the database.
        Constructs a bulk SQL query that uses account names but joins to the
        hive_accounts table (in SCHEMA_NAME) to translate names to ids.

        For mode:
          - FlushMode.INSERT: for follow events. This group may contain both
            NetOp.INSERT and NetOp.UPSERT events. In the INSERT branch we use
            ON CONFLICT DO NOTHING; in the UPSERT branch we use ON CONFLICT DO UPDATE.
          - FlushMode.DELETE: for unfollow events.
          - FlushMode.RESET: for resets (delete all follows for a given follower).

        Returns a list of raw delta tuples (user, delta_followers, delta_following)
        if self.track_deltas is True; otherwise returns an empty list.
        """
        raw_deltas = []
        if mode == FlushMode.INSERT:
            # Separate pure INSERT from UPSERT events.
            # ins_entries = [e for e in entries if e[3] == NetOp.INSERT]
            # upsert_entries = [e for e in entries if e[3] == NetOp.UPSERT]
            ins_entries = []
            upsert_entries = [e for e in entries if e[3] == NetOp.UPSERT or e[3] == NetOp.INSERT]
            if ins_entries:
                # Build a VALUES clause like:
                #   ('alice', 'bob', 1234), ('charlie', 'dave', 1235), ...
                values_clause = ', '.join(
                    f"({follower}, {following}, {block_num})"
                    for (follower, following, block_num, op) in ins_entries
                )
                query = f"""
                WITH ins AS (
                  INSERT INTO {SCHEMA_NAME}.{self.table} (follower, following, block_num)
                  SELECT r.id, g.id, v.block_num
                  FROM (
                    VALUES {values_clause}
                  ) AS v(follower, following, block_num)
                  JOIN {SCHEMA_NAME}.hive_accounts AS r ON v.follower = r.name
                  JOIN {SCHEMA_NAME}.hive_accounts AS g ON v.following = g.name
                  ON CONFLICT (follower, following) DO NOTHING
                  RETURNING follower, following, block_num
                )
                SELECT
                  r.name AS follower_name,
                  g.name AS following_name,
                  ins.block_num
                FROM ins
                JOIN hivemind_app.hive_accounts AS r ON ins.follower = r.id
                JOIN hivemind_app.hive_accounts AS g ON ins.following = g.id;
                """
                rows = db.query_all(query)
                if self.track_deltas:
                    # Each inserted row increases follower's "following" count and
                    # the followed account's "followers" count by 1.
                    for row in rows:
                        follower, following, _ = row
                        raw_deltas.append((follower, 0, +1))
                        raw_deltas.append((following, +1, 0))
            if upsert_entries:
                values_clause = ', '.join(
                    f"({follower}, {following}, {block_num})"
                    for (follower, following, block_num, op) in upsert_entries
                )
                # Here we use the trick (xmax = 0) to tell us whether the row was inserted.
                query = f"""
                WITH ins AS (
                  INSERT INTO {SCHEMA_NAME}.{self.table} (follower, following, block_num)
                  SELECT r.id, g.id, v.block_num
                  FROM (
                    VALUES {values_clause}
                  ) AS v(follower, following, block_num)
                  JOIN {SCHEMA_NAME}.hive_accounts AS r ON v.follower = r.name
                  JOIN {SCHEMA_NAME}.hive_accounts AS g ON v.following = g.name
                  ON CONFLICT (follower, following) DO UPDATE
                    SET block_num = EXCLUDED.block_num
                  RETURNING follower, following, block_num, (xmax = 0) as inserted
                )
                SELECT
                  r.name AS follower_name,
                  g.name AS following_name,
                  ins.block_num,
                  ins.inserted
                FROM ins
                JOIN {SCHEMA_NAME}.hive_accounts AS r ON ins.follower = r.id
                JOIN {SCHEMA_NAME}.hive_accounts AS g ON ins.following = g.id;
                """
                rows = db.query_all(query)
                if self.track_deltas:
                    # For each upsert row, only if "inserted" is true do we treat it as a net new follow.
                    for row in rows:
                        follower, following, _, inserted = row
                        if inserted:
                            raw_deltas.append((follower, 0, +1))
                            raw_deltas.append((following, +1, 0))
        elif mode == FlushMode.DELETE:
            # Build a VALUES clause like:
            #   ('alice', 'bob'), ('charlie', 'dave'), ...
            values_clause = ', '.join(
                f"({follower}, {following})"
                for (follower, following, _, op) in entries
            )
            query = f"""
            WITH del AS (
              DELETE FROM {SCHEMA_NAME}.{self.table} f
              USING {SCHEMA_NAME}.hive_accounts AS follower_acc,
                    {SCHEMA_NAME}.hive_accounts AS following_acc,
                    (VALUES {values_clause}) AS v(follower_name, following_name)
              WHERE f.follower = follower_acc.id
                AND f.following = following_acc.id
                AND follower_acc.name = v.follower_name
                AND following_acc.name = v.following_name
              RETURNING follower_acc.name, following_acc.name
            )
            SELECT * FROM del;
            """
            rows = db.query_all(query)
            if self.track_deltas:
                for row in rows:
                    follower, following = row
                    raw_deltas.append((follower, 0, -1))
                    raw_deltas.append((following, -1, 0))
        elif mode == FlushMode.RESET:
            # Build a VALUES clause like:
            #   ('alice'), ('bob'), ...
            values_clause = ', '.join(
                f"({follower})"
                for (follower, blk) in entries
            )
            # Join again on hive_accounts for the following field so that both names are returned.
            query = f"""
            WITH del AS (
              DELETE FROM {SCHEMA_NAME}.{self.table} f
              USING {SCHEMA_NAME}.hive_accounts AS follower_acc,
                    {SCHEMA_NAME}.hive_accounts AS following_acc,
                    (VALUES {values_clause}) AS v(follower_name)
              WHERE f.follower = follower_acc.id
                AND follower_acc.name = v.follower_name
                AND f.following = following_acc.id
              RETURNING follower_acc.name, following_acc.name
            )
            SELECT * FROM del;
            """
            rows = db.query_all(query)
            if self.track_deltas:
                for row in rows:
                    follower, following = row
                    raw_deltas.append((follower, 0, -1))
                    raw_deltas.append((following, -1, 0))
        else:
            raise ValueError(f"Unknown flush mode: {mode}")
        return raw_deltas

    # --- Public flush method ---
    def flush(self, db):
        """
        Flush all pending operations to the database.
        1. Moves any still-pending events from self.current into groups.
        2. Iterates over all groups, calls _flush_group() to execute bulk SQL,
           and aggregates delta info if track_deltas is True.
        3. Clears all groups.
        4. Returns aggregated delta info as a dictionary {user: (delta_followers, delta_following)}
           if track_deltas is True, otherwise returns None.
        """
        begin_time = time.time()
        # For any still-pending events in current, create a group.
        if self.current:
            ins_entries = []
            del_entries = []
            for key, (op, blk) in self.current.items():
                follower, following = key
                if op in (NetOp.INSERT, NetOp.UPSERT):
                    ins_entries.append((follower, following, blk, op))
                elif op == NetOp.DELETE:
                    del_entries.append((follower, following, None, op))
            if ins_entries:
                self.groups.append((FlushMode.INSERT, ins_entries))
            if del_entries:
                self.groups.append((FlushMode.DELETE, del_entries))
            self.current.clear()

        # Compute the total count of operations across all groups.
        total_count = sum(len(entries) for mode, entries in self.groups)

        all_raw_deltas = []
        for mode, entries in self.groups:
            group_deltas = self._flush_group(db, mode, entries)
            all_raw_deltas.extend(group_deltas)
        self.groups.clear()
        end_time = time.time()
        print(f"{self.table} flush time: {end_time - begin_time} seconds", file=sys.stderr)
        if self.track_deltas:
            return (total_count, self._aggregate_deltas(all_raw_deltas))
        else:
            return (total_count, None)

    def is_empty(self):
        return not self.groups and not self.current


class Follow(DbAdapterHolder):
    """Handles processing of follow-related operations."""
    follows_batches_to_flush = NetEffectTracker('follows', True)
    muted_batches_to_flush = NetEffectTracker('muted')
    blacklisted_batches_to_flush = NetEffectTracker('blacklisted')
    follow_muted_batches_to_flush = NetEffectTracker('follow_muted')
    follow_blacklisted_batches_to_flush = NetEffectTracker('follow_blacklisted')

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
        elif action == FollowAction.Follow:
            for following in op.get('following', []):
                cls.follows_batches_to_flush.add_insert(follower, following, block_num)
                cls.muted_batches_to_flush.add_delete(follower, following, block_num)
        elif action == FollowAction.Mute:
            for following in op.get('following', []):
                cls.muted_batches_to_flush.add_insert(follower, following, block_num)
                cls.follows_batches_to_flush.add_delete(follower, following, block_num)
        elif action == FollowAction.Blacklist:
            for following in op.get('following', []):
                cls.blacklisted_batches_to_flush.add_insert(follower, following, block_num)
        elif action == FollowAction.Unblacklist:
            for following in op.get('following', []):
                cls.blacklisted_batches_to_flush.add_delete(follower, following, block_num)
        elif action == FollowAction.FollowBlacklisted:
            for following in op.get('following', []):
                cls.follow_blacklisted_batches_to_flush.add_insert(follower, following, block_num)
        elif action == FollowAction.UnFollowBlacklisted:
            for following in op.get('following', []):
                cls.follow_blacklisted_batches_to_flush.add_delete(follower, following, block_num)
        elif action == FollowAction.FollowMuted:
            for following in op.get('following', []):
                cls.follow_muted_batches_to_flush.add_insert(follower, following, block_num)
        elif action == FollowAction.UnfollowMuted:
            for following in op.get('following', []):
                cls.follow_muted_batches_to_flush.add_delete(follower, following, block_num)
        elif action == FollowAction.ResetBlacklist:
            cls.blacklisted_batches_to_flush.add_reset(follower, block_num)
        elif action == FollowAction.ResetFollowingList:
            cls.follows_batches_to_flush.add_reset(follower, block_num)
        elif action == FollowAction.ResetMutedList:
            cls.muted_batches_to_flush.add_reset(follower, block_num)
        elif action == FollowAction.ResetFollowBlacklist:
            cls.follow_blacklisted_batches_to_flush.add_reset(follower, block_num)
            cls.follow_blacklisted_batches_to_flush.add_insert(follower, "'null'", block_num)
        elif action == FollowAction.ResetFollowMutedList:
            cls.follow_muted_batches_to_flush.add_reset(follower, block_num)
            cls.follow_muted_batches_to_flush.add_insert(follower, "'null'", block_num)
        elif action == FollowAction.ResetAllLists:
            cls.blacklisted_batches_to_flush.add_reset(follower, block_num)
            cls.follows_batches_to_flush.add_reset(follower, block_num)
            cls.muted_batches_to_flush.add_reset(follower, block_num)
            cls.follow_blacklisted_batches_to_flush.add_reset(follower, block_num)
            cls.follow_muted_batches_to_flush.add_reset(follower, block_num)
            cls.follow_blacklisted_batches_to_flush.add_insert(follower, "'null'", block_num)
            cls.follow_muted_batches_to_flush.add_insert(follower, "'null'", block_num)

    @classmethod
    def flush(cls):
        """Flush accumulated follow operations to the database in batches."""
        if (cls.follows_batches_to_flush.is_empty() and
            cls.muted_batches_to_flush.is_empty() and
            cls.blacklisted_batches_to_flush.is_empty() and
            cls.follow_muted_batches_to_flush.is_empty() and
            cls.follow_blacklisted_batches_to_flush.is_empty()):
            return (0, {})

        cls.beginTx()

        (follow_op_count, follow_count_deltas) = cls.follows_batches_to_flush.flush(cls.db)
        (muted_op_count, _) = cls.muted_batches_to_flush.flush(cls.db)
        (blacklisted_op_count, _) = cls.blacklisted_batches_to_flush.flush(cls.db)
        (follow_muted_op_count, _) = cls.follow_muted_batches_to_flush.flush(cls.db)
        (follow_blacklisted_op_count, _) = cls.follow_blacklisted_batches_to_flush.flush(cls.db)

        before_commit = time.time()
        cls.commitTx()
        after_commit = time.time()
        print(f"commit time: {after_commit - before_commit:.2f} seconds")

        total_op_count = follow_op_count + muted_op_count +  blacklisted_op_count + follow_muted_op_count + follow_blacklisted_op_count
        # log.info(f"follow_op_count was {follow_op_count}")
        return (total_op_count, follow_count_deltas)
