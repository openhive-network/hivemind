""" Votes indexing and processing """

import collections
import logging
from itertools import count

from hive.conf import SCHEMA_NAME
from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.utils.normalize import escape_characters
from hive.utils.misc import chunks

log = logging.getLogger(__name__)


class Votes(DbAdapterHolder):
    """Class for managing posts votes"""

    _votes_data = collections.OrderedDict()
    _votes_per_post = {}
    _vote_notifications = collections.OrderedDict()
    _notification_first_block = None

    inside_flush = False

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

        if key in cls._votes_data:
            vote_data = cls._votes_data[key]
            vote_data["vote_percent"] = weight
            vote_data["last_update"] = date
            n = cls._vote_notifications[key]
            n['last_update'] = date
            n['block_num'] = block_num
            # only effective vote edits increase num_changes counter
        else:
            if not post_key in cls._votes_per_post:
                cls._votes_per_post[post_key] = []
            cls._votes_per_post[post_key].append(voter)
            cls._votes_data[key] = dict(
                voter=voter,
                author=author,
                permlink=escape_characters(permlink),
                vote_percent=weight,
                weight=0,
                rshares=0,
                last_update=date,
                is_effective=False,
                num_changes=0,
                block_num=block_num,
            )
            cls._vote_notifications[key] = {
                'block_num': block_num,
                'voter': voter,
                'author': author,
                'permlink': permlink,
                'last_update': date,
                'rshares': 0,
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
                del cls._vote_notifications[key]
            del cls._votes_per_post[post_key]

    @classmethod
    def effective_comment_vote_op(cls, vop):
        """Process effective_comment_vote_operation"""

        post_key = f"{vop['author']}/{vop['permlink']}"
        key = f"{vop['voter']}/{post_key}"

        if key in cls._votes_data:
            vote_data = cls._votes_data[key]
            vote_data["weight"] = vop["weight"]
            vote_data["rshares"] = vop["rshares"]
            vote_data["is_effective"] = True
            vote_data["num_changes"] += 1
            vote_data["block_num"] = vop["block_num"]
            n = cls._vote_notifications[key]
            n['rshares'] = vop["rshares"]
            n['block_num'] = vop["block_num"]
        else:
            if not post_key in cls._votes_per_post:
                cls._votes_per_post[post_key] = []
            cls._votes_per_post[post_key].append(vop['voter'])
            cls._votes_data[key] = dict(
                voter=vop["voter"],
                author=vop["author"],
                permlink=escape_characters(vop["permlink"]),
                vote_percent=0,
                weight=vop["weight"],
                rshares=vop["rshares"],
                last_update="1970-01-01 00:00:00",
                is_effective=True,
                num_changes=0,
                block_num=vop["block_num"],
            )
            cls._vote_notifications[key] = {
                'block_num': vop["block_num"],
                'voter': vop["voter"],
                'author': vop["author"],
                'permlink': vop["permlink"],
                'last_update': "1970-01-01 00:00:00",
                'rshares': vop["rshares"],
                }

    @classmethod
    def flush_notifications(cls):
        if cls._notification_first_block is None:
            cls._notification_first_block = cls.db.query_row("select hivemind_app.block_before_irreversible( '90 days' ) AS num")['num']
        n = len(cls._vote_notifications)
        max_block_num = max(n['block_num'] for k,n in (cls._vote_notifications or {'': {'block_num': 0} }).items())
        if n > 0 and max_block_num > cls._notification_first_block:
            sql = f"""
                INSERT INTO {SCHEMA_NAME}.hive_notification_cache
                (block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
                SELECT hn.block_num, 17, hn.last_update AS created_at, hn.src, hn.dst, hn.post_id, hn.post_id, hn.score, {SCHEMA_NAME}.format_vote_value_payload(vote_value) as payload, '', ''
                FROM (
                    SELECT n.*,
                      hv.id AS src,
                      hpv.author_id AS dst,
                      hpv.id AS post_id,
                      hivemind_app.calculate_value_of_vote_on_post(hpv.payout + hpv.pending_payout, hpv.rshares, n.rshares) AS vote_value,
                      hivemind_app.calculate_notify_vote_score(hpv.payout + hpv.pending_payout, hpv.abs_rshares, n.rshares) AS score
                    FROM
                    (VALUES {{}})
                    AS n(block_num, voter, author, permlink, last_update, rshares)
                    JOIN {SCHEMA_NAME}.hive_accounts AS hv ON n.voter = hv.name
                    JOIN {SCHEMA_NAME}.hive_accounts AS ha ON n.author = ha.name
                    JOIN {SCHEMA_NAME}.hive_permlink_data AS pd ON n.permlink = pd.permlink
                    JOIN (
                        SELECT hpvi.id, hpvi.author_id, hpvi.payout, hpvi.pending_payout, hpvi.abs_rshares, hpvi.vote_rshares as rshares
                        FROM {SCHEMA_NAME}.hive_posts hpvi
                        WHERE hpvi.block_num > hivemind_app.block_before_head('97 days'::interval)
                    ) hpv ON pd.id = hpv.id AND ha.id = hpv.author_id
                ) AS hn
                WHERE hn.block_num > hivemind_app.block_before_irreversible( '90 days' )
                    AND score >= 0
                    AND hn.src IS DISTINCT FROM hn.dst
                    AND hn.rshares >= 10e9
                    AND hn.vote_value >= 0.02
                ORDER BY hn.block_num, created_at, hn.src, hn.dst
                ON CONFLICT (src, dst, type_id, post_id) DO UPDATE
                SET block_num=EXCLUDED.block_num, created_at=EXCLUDED.created_at
            """
            for chunk in chunks(cls._vote_notifications, 1000):
                cls.beginTx()
                values_str = ','.join(f"({n['block_num']}, {escape_characters(n['voter'])}, {escape_characters(n['author'])}, {escape_characters(n['permlink'])}, {escape_characters(n['last_update'])}::timestamp, {n['rshares']})" for k,n in chunk.items())
                cls.db.query_prepared(sql.format(values_str))
                cls.commitTx()
        else:
            n = 0
        cls._vote_notifications.clear()
        return n

    @classmethod
    def flush_votes(cls):
        """Flush vote data from cache to database"""

        cls.inside_flush = True
        n = 0
        if cls._votes_data:
            sql = f"""
                INSERT INTO {SCHEMA_NAME}.hive_votes
                (post_id, voter_id, author_id, permlink_id, weight, rshares, vote_percent, last_update, num_changes, block_num, is_effective)

                SELECT hp.id as post_id, ha_v.id as voter_id, ha_a.id as author_id, hpd_p.id as permlink_id,
                t.weight, t.rshares, t.vote_percent, t.last_update, t.num_changes, t.block_num, t.is_effective
                FROM
                (
                VALUES
                  -- order_id, voter, author, permlink, weight, rshares, vote_percent, last_update, num_changes, block_num, is_effective
                  {{}}
                ) AS T(order_id, voter, author, permlink, weight, rshares, vote_percent, last_update, num_changes, block_num, is_effective)
                INNER JOIN {SCHEMA_NAME}.hive_accounts ha_v ON ha_v.name = t.voter
                INNER JOIN {SCHEMA_NAME}.hive_accounts ha_a ON ha_a.name = t.author
                INNER JOIN {SCHEMA_NAME}.hive_permlink_data hpd_p ON hpd_p.permlink = t.permlink
                INNER JOIN {SCHEMA_NAME}.hive_posts hp ON hp.author_id = ha_a.id AND hp.permlink_id = hpd_p.id
                WHERE hp.counter_deleted = 0
                ORDER BY t.order_id
                ON CONFLICT ON CONSTRAINT hive_votes_voter_id_author_id_permlink_id_uk DO
                UPDATE
                  SET
                    weight = CASE EXCLUDED.is_effective WHEN true THEN EXCLUDED.weight ELSE {SCHEMA_NAME}.hive_votes.weight END,
                    rshares = CASE EXCLUDED.is_effective WHEN true THEN EXCLUDED.rshares ELSE {SCHEMA_NAME}.hive_votes.rshares END,
                    vote_percent = EXCLUDED.vote_percent,
                    last_update = EXCLUDED.last_update,
                    num_changes = {SCHEMA_NAME}.hive_votes.num_changes + EXCLUDED.num_changes + 1,
                    block_num = EXCLUDED.block_num
                  WHERE {SCHEMA_NAME}.hive_votes.voter_id = EXCLUDED.voter_id and {SCHEMA_NAME}.hive_votes.author_id = EXCLUDED.author_id and {SCHEMA_NAME}.hive_votes.permlink_id = EXCLUDED.permlink_id
                RETURNING post_id
                """
            # WHERE clause above seems superfluous (and works all the same without it, at least up to 5mln)

            cnt = count()
            for chunk in chunks(cls._votes_data, 1000):
                cls.beginTx()
                values_str = ','.join(
                    "({}, '{}', '{}', {}, {}, {}, {}, '{}'::timestamp, {}, {}, {})".format(
                        next(cnt),  # for ordering
                        vd['voter'],
                        vd['author'],
                        vd['permlink'],
                        vd['weight'],
                        vd['rshares'],
                        vd['vote_percent'],
                        vd['last_update'],
                        vd['num_changes'],
                        vd['block_num'],
                        vd['is_effective'],
                    ) for k,vd in chunk.items()
                )
                actual_query = sql.format(values_str)
                post_ids = cls.db.query_prepared_all(actual_query)
                cls.db.query_no_return('SELECT pg_advisory_xact_lock(777)')  # synchronise with update hive_posts in posts
                cls.db.query_no_return("SELECT * FROM hivemind_app.update_posts_rshares(:post_ids)", post_ids=[id[0] for id in post_ids])
                cls.commitTx()

            n = len(cls._votes_data)
            cls._votes_data.clear()
            cls._votes_per_post.clear()

        cls.inside_flush = False

        return n

    @classmethod
    def flush(cls):
        return cls.flush_votes() + cls.flush_notifications()
