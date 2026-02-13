"""Votes indexing and processing"""

import collections
import logging
from itertools import count

from hive.conf import SCHEMA_NAME
from hive.db.db_state import DbState
from hive.indexer.accounts import Accounts
from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.indexer.notification_cache import NotificationCache
from hive.utils.misc import UniqueCounter, chunks

log = logging.getLogger(__name__)


class Votes(DbAdapterHolder):
    """Class for managing posts votes"""

    _votes_data = collections.OrderedDict()
    _votes_per_post = {}
    _counter = UniqueCounter()
    _post_id_cache = {}  # (author_id, permlink) -> (post_id, permlink_id); massive sync only
    inside_flush = False

    @classmethod
    def _should_accumulate_vote_notification(cls, block_num):
        """Check if a vote at this block should accumulate a notification.

        During massive sync, P8 skips all notification accumulation. But vote
        notifications need to be accumulated regardless of sync stage so they
        can be flushed at finalization with correct rshares. We limit to the
        90-day notification window to bound memory usage.
        """
        return not NotificationCache.should_skip_for_block(block_num)

    @classmethod
    def vote_op(cls, vote_operation, date):
        """Process vote_operation"""
        voter = vote_operation['voter']
        author = vote_operation['author']
        permlink = vote_operation['permlink']
        weight = vote_operation['weight']
        block_num = vote_operation['block_num']

        if cls.inside_flush:
            log.exception("Adding new vote-info into '_votes_data' dict")
            raise RuntimeError("Fatal error")

        post_key = f"{author}/{permlink}"
        key = f"{voter}/{post_key}"

        accumulate_vote_notif = cls._should_accumulate_vote_notification(block_num)
        if key in cls._votes_data:
            vote_data = cls._votes_data[key]
            vote_data["vote_percent"] = weight
            vote_data["last_update"] = date
            if accumulate_vote_notif and key in NotificationCache.vote_notifications:
                n = NotificationCache.vote_notifications[key]
                n['last_update'] = date
                n['block_num'] = block_num
                n['counter'] = cls._counter.increment(block_num)
            # only effective vote edits increase num_changes counter
        else:
            if post_key not in cls._votes_per_post:
                cls._votes_per_post[post_key] = []
            cls._votes_per_post[post_key].append(voter)
            cls._votes_data[key] = dict(
                voter=voter,
                voter_id=Accounts.get_id(voter),
                author=author,
                author_id=Accounts.get_id(author),
                permlink=permlink,
                vote_percent=weight,
                weight=0,
                rshares=0,
                last_update=date,
                is_effective=False,
                num_changes=0,
                block_num=block_num,
            )
            if accumulate_vote_notif:
                NotificationCache.vote_notifications[key] = {
                    'block_num': block_num,
                    'voter': voter,
                    'author': author,
                    'permlink': permlink,
                    'last_update': date,
                    'rshares': 0,
                    'counter': cls._counter.increment(block_num),
                }

    @classmethod
    def drop_votes_of_deleted_comment(cls, comment_delete_operation):
        """Remove cached votes for comment that was deleted"""
        # ABW: note that it only makes difference when comment was deleted and its author/permlink
        # reused in the same pack of blocks - in case of no reuse, votes on deleted comment won't
        # make it to the DB due to "counter_deleted = 0" condition and "INNER JOIN hive_posts"
        # while votes from previous packs will remain in DB (they can be accessed with
        # database_api.list_votes so it is not entirely inconsequential)
        post_key = f"{comment_delete_operation['author']}/{comment_delete_operation['permlink']}"
        if post_key in cls._votes_per_post:
            for voter in cls._votes_per_post[post_key]:
                key = f"{voter}/{post_key}"
                del cls._votes_data[key]
                NotificationCache.vote_notifications.pop(key, None)
            del cls._votes_per_post[post_key]
        # Evict from post_id cache so a recreated post with same author/permlink gets fresh lookup
        cache_key = (Accounts.get_id(comment_delete_operation['author']), comment_delete_operation['permlink'])
        cls._post_id_cache.pop(cache_key, None)

    @classmethod
    def effective_comment_vote_op(cls, vop):
        """Process effective_comment_vote_operation"""

        block_num = vop["block_num"]
        post_key = f"{vop['author']}/{vop['permlink']}"
        key = f"{vop['voter']}/{post_key}"

        accumulate_vote_notif = cls._should_accumulate_vote_notification(block_num)
        if key in cls._votes_data:
            vote_data = cls._votes_data[key]
            vote_data["weight"] = vop["weight"]
            vote_data["rshares"] = vop["rshares"]
            vote_data["is_effective"] = True
            vote_data["num_changes"] += 1
            vote_data["block_num"] = block_num
            if accumulate_vote_notif and key in NotificationCache.vote_notifications:
                n = NotificationCache.vote_notifications[key]
                n['rshares'] = vop["rshares"]
                n['block_num'] = block_num
                n['counter'] = cls._counter.increment(block_num)
        else:
            if post_key not in cls._votes_per_post:
                cls._votes_per_post[post_key] = []
            cls._votes_per_post[post_key].append(vop['voter'])
            cls._votes_data[key] = dict(
                voter=vop["voter"],
                voter_id=Accounts.get_id(vop["voter"]),
                author=vop["author"],
                author_id=Accounts.get_id(vop["author"]),
                permlink=vop["permlink"],
                vote_percent=0,
                weight=vop["weight"],
                rshares=vop["rshares"],
                last_update="1970-01-01 00:00:00",
                is_effective=True,
                num_changes=0,
                block_num=block_num,
            )
            if accumulate_vote_notif:
                NotificationCache.vote_notifications[key] = {
                    'block_num': block_num,
                    'voter': vop["voter"],
                    'author': vop["author"],
                    'permlink': vop["permlink"],
                    'last_update': "1970-01-01 00:00:00",
                    'rshares': vop["rshares"],
                    'counter': cls._counter.increment(block_num),
                }

    @classmethod
    def flush_votes(cls):
        """Flush vote data from cache to database"""

        cls.inside_flush = True
        n = 0
        if not DbState.is_massive_sync() and cls._post_id_cache:
            cls._post_id_cache.clear()  # free memory when entering live sync
        if cls._votes_data:
            if DbState.is_massive_sync():
                n = cls._flush_votes_massive()
            else:
                n = cls._flush_votes_live()
            cls._votes_data.clear()
            cls._votes_per_post.clear()
        cls.inside_flush = False

        return n

    @classmethod
    def _resolve_post_ids(cls, needed, db=None):
        """Bulk-resolve (author_id, permlink) pairs to (post_id, permlink_id) via DB.

        Updates _post_id_cache with results. Pairs not found (deleted posts) are not cached.
        """
        if not needed:
            return
        if db is None:
            db = cls.db
        needed_list = list(needed)
        for i in range(0, len(needed_list), 2000):
            batch = needed_list[i : i + 2000]
            placeholders = ','.join(['(%s, %s)'] * len(batch))
            params = []
            for author_id, permlink in batch:
                params.extend([author_id, permlink])
            sql = f"""
                SELECT t.author_id, t.permlink, hp.id AS post_id, hpd.id AS permlink_id
                FROM (VALUES {placeholders}) AS t(author_id, permlink)
                INNER JOIN {SCHEMA_NAME}.hive_permlink_data hpd ON hpd.permlink = t.permlink
                INNER JOIN {SCHEMA_NAME}.hive_posts hp
                  ON hp.author_id = t.author_id AND hp.permlink_id = hpd.id AND hp.counter_deleted = 0
            """
            rows = db.query_all_raw(sql, tuple(params))
            for row in rows:
                cls._post_id_cache[(row[0], row[1])] = (row[2], row[3])

    @classmethod
    def _flush_votes_massive(cls):
        """Flush votes during massive sync using post_id cache to avoid JOINs."""
        return cls._do_flush_votes_massive(cls.db, use_own_tx=True)

    @classmethod
    def flush_votes_in_existing_tx(cls, db):
        """Flush accumulated votes inside an existing transaction (no BEGIN/COMMIT).

        Called from the main batch transaction in process_multi_* methods.
        Clears _votes_data after flushing so the concurrent flush is a no-op.
        """
        cls.inside_flush = True
        n = 0
        if cls._votes_data:
            n = cls._do_flush_votes_massive(db, use_own_tx=False)
            cls._votes_data.clear()
            cls._votes_per_post.clear()
        cls.inside_flush = False
        return n

    @classmethod
    def _do_flush_votes_massive(cls, db, use_own_tx: bool):
        """Core massive sync vote flush logic.

        Args:
            db: Database adapter to use for queries.
            use_own_tx: If True, wrap each chunk in BEGIN/COMMIT (old behavior).
                       If False, assume caller manages the transaction.
        """
        # Collect unique (author_id, permlink) pairs and find cache misses
        needed = set()
        for vd in cls._votes_data.values():
            key = (vd['author_id'], vd['permlink'])
            if key not in cls._post_id_cache:
                needed.add(key)

        # Bulk-resolve cache misses
        if needed:
            cls._resolve_post_ids(needed, db)

        # Build direct INSERT values (no JOINs)
        sql_template = f"""
            INSERT INTO {SCHEMA_NAME}.hive_votes
            (post_id, voter_id, author_id, permlink_id, weight, rshares, vote_percent,
             last_update, num_changes, block_num, is_effective)
            VALUES {{}}
            ON CONFLICT ON CONSTRAINT hive_votes_voter_id_author_id_permlink_id_uk DO
            UPDATE SET
              post_id = EXCLUDED.post_id,
              weight = CASE EXCLUDED.is_effective WHEN true THEN EXCLUDED.weight ELSE {SCHEMA_NAME}.hive_votes.weight END,
              rshares = CASE EXCLUDED.is_effective WHEN true THEN EXCLUDED.rshares ELSE {SCHEMA_NAME}.hive_votes.rshares END,
              vote_percent = EXCLUDED.vote_percent,
              last_update = EXCLUDED.last_update,
              num_changes = {SCHEMA_NAME}.hive_votes.num_changes + EXCLUDED.num_changes + 1,
              block_num = EXCLUDED.block_num
            WHERE {SCHEMA_NAME}.hive_votes.voter_id = EXCLUDED.voter_id
              AND {SCHEMA_NAME}.hive_votes.author_id = EXCLUDED.author_id
              AND {SCHEMA_NAME}.hive_votes.permlink_id = EXCLUDED.permlink_id
        """

        batch_values = []
        batch_params = []
        for vd in cls._votes_data.values():
            cache_key = (vd['author_id'], vd['permlink'])
            cached = cls._post_id_cache.get(cache_key)
            if cached is None:
                continue  # post not found (deleted) — matches INNER JOIN behavior
            post_id, permlink_id = cached
            batch_values.append('(%s, %s, %s, %s, %s, %s, %s, %s::timestamp, %s, %s, %s)')
            batch_params.extend(
                [
                    post_id,
                    vd['voter_id'],
                    vd['author_id'],
                    permlink_id,
                    vd['weight'],
                    vd['rshares'],
                    vd['vote_percent'],
                    vd['last_update'],
                    vd['num_changes'],
                    vd['block_num'],
                    vd['is_effective'],
                ]
            )
            if len(batch_values) >= 2000:
                if use_own_tx:
                    cls.beginTx()
                db.query_no_return_raw(sql_template.format(','.join(batch_values)), tuple(batch_params))
                if use_own_tx:
                    cls.commitTx()
                batch_values = []
                batch_params = []

        if batch_values:
            if use_own_tx:
                cls.beginTx()
            db.query_no_return_raw(sql_template.format(','.join(batch_values)), tuple(batch_params))
            if use_own_tx:
                cls.commitTx()

        return len(cls._votes_data)

    @classmethod
    def _flush_votes_live(cls):
        """Flush votes during live sync (original logic with JOINs and RETURNING)."""
        sql_template = f"""
            INSERT INTO {SCHEMA_NAME}.hive_votes
            (post_id, voter_id, author_id, permlink_id, weight, rshares, vote_percent, last_update, num_changes, block_num, is_effective)

            SELECT hp.id, t.voter_id, t.author_id, hpd_p.id,
            t.weight, t.rshares, t.vote_percent, t.last_update, t.num_changes, t.block_num, t.is_effective
            FROM
            (VALUES {{}})
            AS t(order_id, voter_id, author_id, permlink, weight, rshares, vote_percent, last_update, num_changes, block_num, is_effective)
            INNER JOIN {SCHEMA_NAME}.hive_permlink_data hpd_p ON hpd_p.permlink = t.permlink
            INNER JOIN {SCHEMA_NAME}.hive_posts hp ON hp.author_id = t.author_id AND hp.permlink_id = hpd_p.id
            WHERE hp.counter_deleted = 0
            ORDER BY t.order_id
            ON CONFLICT ON CONSTRAINT hive_votes_voter_id_author_id_permlink_id_uk DO
            UPDATE
              SET
                post_id = EXCLUDED.post_id,
                weight = CASE EXCLUDED.is_effective WHEN true THEN EXCLUDED.weight ELSE {SCHEMA_NAME}.hive_votes.weight END,
                rshares = CASE EXCLUDED.is_effective WHEN true THEN EXCLUDED.rshares ELSE {SCHEMA_NAME}.hive_votes.rshares END,
                vote_percent = EXCLUDED.vote_percent,
                last_update = EXCLUDED.last_update,
                num_changes = {SCHEMA_NAME}.hive_votes.num_changes + EXCLUDED.num_changes + 1,
                block_num = EXCLUDED.block_num
              WHERE {SCHEMA_NAME}.hive_votes.voter_id = EXCLUDED.voter_id AND {SCHEMA_NAME}.hive_votes.author_id = EXCLUDED.author_id AND {SCHEMA_NAME}.hive_votes.permlink_id = EXCLUDED.permlink_id
            RETURNING post_id
            """

        cnt = count()
        for chunk in chunks(cls._votes_data, 1000):
            items = list(chunk.values())
            placeholders = ','.join(['(%s, %s, %s, %s, %s, %s, %s, %s::timestamp, %s, %s, %s)'] * len(items))
            params = []
            for vd in items:
                params.extend(
                    [
                        next(cnt),
                        vd['voter_id'],
                        vd['author_id'],
                        vd['permlink'],
                        vd['weight'],
                        vd['rshares'],
                        vd['vote_percent'],
                        vd['last_update'],
                        vd['num_changes'],
                        vd['block_num'],
                        vd['is_effective'],
                    ]
                )
            cls.beginTx()
            actual_query = sql_template.format(placeholders)
            post_ids = cls.db.query_all_raw(actual_query, tuple(params))
            cls.db.query_no_return('SELECT pg_advisory_xact_lock(777)')  # synchronise with update hive_posts in posts
            cls.db.query_no_return(
                "SELECT * FROM hivemind_app.update_posts_rshares(:post_ids)",
                post_ids=[id[0] for id in post_ids],
            )
            cls.commitTx()

        return len(cls._votes_data)

    @classmethod
    def flush(cls):
        return cls.flush_votes()
