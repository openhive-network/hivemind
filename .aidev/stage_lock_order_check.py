"""Check that the massive sync statements of both pipelined stages lock hive_posts rows in id order.

Pipelined massive sync runs a batch's posts phase and community post ops (Stage A) beside
the previous batch's payouts and rshares update (Stage B); both write the same hive_posts
rows. On the installed hivemind, with two committed posts `low` < `high` and a vote on each
(removed at the end), and each stage's own operations staged in its own transaction (rolled
back):

- order: with `low` locked by another session, each statement waits on `low` without
  holding `high`, although its operations name `high` first;
- overlap: with `high` held, Stage A's posts phase (editing `high` then `low`) and Stage B's
  payouts, then its rshares update, then its payouts in partitions, on both posts finish
  without a deadlock once `high` is released;
- partitions: the payout partitions update each post exactly once between them.

The other sessions lock FOR NO KEY UPDATE: it conflicts with every lock the stages take, and
not with the FOR KEY SHARE locks an installed database's foreign key checks take (massive sync
drops the foreign keys).

  python3 .aidev/stage_lock_order_check.py <hivemind url>
"""

from __future__ import annotations

import json
import sys
import threading
import time
from collections.abc import Callable, Mapping, Sequence

import psycopg2
import psycopg2.errors
import psycopg2.extensions
from psycopg2.extensions import cursor as Cursor

AUTHOR = 'slo-a'
PERMLINKS = ('slo-low', 'slo-high')
CATEGORY = 'slo-cat'
BLOCK = 2_000_000_400
WAIT_S = 30


def _connect(url: str, name: str) -> psycopg2.extensions.connection:
    conn = psycopg2.connect(url, application_name=f'stage_lock_order_check {name}')
    conn.autocommit = True
    with conn.cursor() as cur:
        cur.execute("SET statement_timeout = '120s'")
    return conn


def _scalar(cur: Cursor) -> int:
    """The first column of the row the last statement returned."""
    row = cur.fetchone()
    if row is None:
        raise AssertionError("the statement returned no row")
    return int(row[0])


def _stage_ops(cur: Cursor, first_id: int, ops: Sequence[tuple[int, Mapping[str, object]]]) -> None:
    """Stage (op_type_id, val) ops at BLOCK, in list order."""
    for n, (op_type_id, val) in enumerate(ops):
        cur.execute(
            "INSERT INTO hivemind_app._ops_staging (id, block_num, block_date, op_type_id, val) "
            "VALUES (%s, %s, '2016-06-03'::TIMESTAMP + %s * INTERVAL '3 seconds', %s, %s::jsonb)",
            (first_id + n, BLOCK, BLOCK - 2_000_000_000, op_type_id, json.dumps(val)),
        )


def _comment(permlink: str) -> tuple[int, dict[str, object]]:
    return 1, {
        'author': AUTHOR,
        'permlink': permlink,
        'parent_author': '',
        'parent_permlink': CATEGORY,
        'title': '',
        'body': 'edited',
        'json_metadata': '{}',
    }


def _posts_phase(cur: Cursor) -> None:
    _stage_ops(cur, 20_000_004_000, [_comment('slo-high'), _comment('slo-low')])
    cur.execute("SELECT count(*) FROM hivemind_app.process_posts_from_staging(2147483647)")


def _community_post_ops(cur: Cursor) -> None:
    ops = [
        (
            18,
            {
                'id': 'community',
                'required_auths': [],
                'required_posting_auths': [AUTHOR],
                'json': json.dumps(
                    ['mutePost', {'community': 'hive-100000', 'account': AUTHOR, 'permlink': permlink, 'notes': ''}]
                ),
            },
        )
        for permlink in ('slo-high', 'slo-low')
    ]
    _stage_ops(cur, 20_000_004_020, ops)
    cur.execute("SELECT hivemind_app.process_community_from_staging(0, 2)")


def _payouts(cur: Cursor) -> None:
    ops = [(61, {'author': AUTHOR, 'permlink': p}) for p in ('slo-high', 'slo-low')]
    _stage_ops(cur, 20_000_004_010, ops)
    cur.execute("SELECT hivemind_app.process_payouts_from_staging(0)")


PAYOUT_PARTS = 4


def _payout_partitions(cur: Cursor) -> None:
    """The payouts as massive sync's partitions apply them, one after another in one transaction."""
    ops = [(61, {'author': AUTHOR, 'permlink': p}) for p in ('slo-high', 'slo-low')]
    _stage_ops(cur, 20_000_004_030, ops)
    updated = 0
    for part in range(PAYOUT_PARTS):
        cur.execute("SELECT hivemind_app.process_payouts_from_staging(0, %s, %s)", (part, PAYOUT_PARTS))
        updated += _scalar(cur)
    if updated != len(ops):
        raise AssertionError(f"the {PAYOUT_PARTS} payout partitions updated {updated} posts, expected {len(ops)}")


def _rshares(posts: dict[str, int]) -> Callable[[Cursor], None]:
    def run(cur: Cursor) -> None:
        cur.execute("SELECT hivemind_app.update_posts_rshares(%s)", ([posts['slo-high'], posts['slo-low']],))

    return run


class _Session(threading.Thread):
    """Runs one stage's statement in a transaction it rolls back; keeps the error it raised."""

    def __init__(self, url: str, name: str, statement: Callable[[Cursor], None]) -> None:
        super().__init__(name=name)
        self.conn = _connect(url, name)
        with self.conn.cursor() as cur:
            cur.execute("SELECT pg_backend_pid()")
            self.pid = _scalar(cur)
        self.statement = statement
        self.error: Exception | None = None

    def run(self) -> None:
        try:
            with self.conn.cursor() as cur:
                cur.execute("BEGIN")
                try:
                    self.statement(cur)
                finally:
                    cur.execute("ROLLBACK")
        except psycopg2.Error as err:
            self.error = err
        finally:
            self.conn.close()


def _wait_for_lock_wait(cur: Cursor, session: _Session) -> None:
    deadline = time.monotonic() + WAIT_S
    while time.monotonic() < deadline:
        cur.execute("SELECT wait_event_type FROM pg_stat_activity WHERE pid = %s", (session.pid,))
        row = cur.fetchone()
        if row is not None and row[0] == 'Lock':
            return
        if not session.is_alive():
            raise AssertionError(f"{session.name} finished without waiting on the held row: {session.error}")
        time.sleep(0.1)
    raise AssertionError(f"{session.name} did not wait on the held row within {WAIT_S} s")


def _finish(session: _Session) -> None:
    session.join(WAIT_S * 4)
    if session.is_alive():
        raise AssertionError(f"{session.name} did not finish")
    if session.error is not None:
        raise AssertionError(f"{session.name} failed: {session.error!r}")


def _hold(url: str, post_id: int) -> psycopg2.extensions.connection:
    holder = _connect(url, 'holder')
    with holder.cursor() as cur:
        cur.execute("BEGIN")
        cur.execute("SELECT 1 FROM hivemind_app.hive_posts WHERE id = %s FOR NO KEY UPDATE", (post_id,))
    return holder


def _release(holder: psycopg2.extensions.connection) -> None:
    with holder.cursor() as cur:
        cur.execute("ROLLBACK")
    holder.close()


def check_order(url: str, cur: Cursor, posts: dict[str, int], name: str, statement: Callable[[Cursor], None]) -> None:
    """While `name` waits on `low`, `high` must not be locked: it locks low before high."""
    holder = _hold(url, posts['slo-low'])
    session = _Session(url, name, statement)
    session.start()
    try:
        _wait_for_lock_wait(cur, session)
        cur.execute("BEGIN")
        try:
            cur.execute(
                "SELECT 1 FROM hivemind_app.hive_posts WHERE id = %s FOR NO KEY UPDATE NOWAIT", (posts['slo-high'],)
            )
        except psycopg2.errors.LockNotAvailable as err:
            raise AssertionError(f"{name} locked post high ({posts['slo-high']}) before post low") from err
        finally:
            cur.execute("ROLLBACK")
    finally:
        _release(holder)
        _finish(session)
    print(f"order: {name} waited on post low without holding post high")


def check_overlap(
    url: str, cur: Cursor, posts: dict[str, int], stage_b: str, statement: Callable[[Cursor], None]
) -> None:
    """Stage A's posts phase and a Stage B statement on the same two posts must not deadlock."""
    holder = _hold(url, posts['slo-high'])
    a = _Session(url, 'posts phase', _posts_phase)
    b = _Session(url, stage_b, statement)
    try:
        a.start()
        _wait_for_lock_wait(cur, a)
        b.start()
        _wait_for_lock_wait(cur, b)
    finally:
        _release(holder)
        for session in (a, b):
            if session.ident is not None:
                _finish(session)
    print(f"overlap: posts phase and {stage_b} on the same posts finished without a deadlock")


def _seed(cur: Cursor) -> dict[str, int]:
    cur.execute("SELECT count(*) FROM hivemind_app._ops_staging")
    if _scalar(cur) != 0:
        raise AssertionError("the check needs an empty hivemind_app._ops_staging (no sync in progress)")
    cur.execute(
        "INSERT INTO hivemind_app.hive_accounts (id, name, created_at) "
        "SELECT COALESCE(max(id), 0) + 1, %s, '2016-06-01' FROM hivemind_app.hive_accounts RETURNING id",
        (AUTHOR,),
    )
    author_id = _scalar(cur)
    cur.execute("INSERT INTO hivemind_app.hive_category_data (category) VALUES (%s) RETURNING id", (CATEGORY,))
    category_id = _scalar(cur)
    posts = {}
    for permlink in PERMLINKS:
        cur.execute("INSERT INTO hivemind_app.hive_permlink_data (permlink) VALUES (%s) RETURNING id", (permlink,))
        permlink_id = _scalar(cur)
        cur.execute(
            "INSERT INTO hivemind_app.hive_posts "
            "(id, root_id, parent_id, author_id, permlink_id, category_id, created_at, depth, block_num, block_num_created) "
            "SELECT n.id, n.id, 0, %s, %s, %s, '2016-06-03', 0, %s, %s "
            "FROM (SELECT nextval('hivemind_app.hive_posts_id_seq')::INT AS id) n RETURNING id",
            (author_id, permlink_id, category_id, BLOCK - 100, BLOCK - 100),
        )
        posts[permlink] = _scalar(cur)
        cur.execute(
            "INSERT INTO hivemind_app.hive_votes (post_id, voter_id, author_id, permlink_id, rshares, block_num) "
            "VALUES (%s, %s, %s, %s, 1000, %s)",
            (posts[permlink], author_id, author_id, permlink_id, BLOCK - 50),
        )
    if not posts['slo-low'] < posts['slo-high']:
        raise AssertionError(f"seeded post ids are not ordered: {posts}")
    return posts


def _clean(cur: Cursor) -> None:
    cur.execute(
        "DELETE FROM hivemind_app.hive_votes hv USING hivemind_app.hive_accounts ha "
        "WHERE ha.name = %s AND hv.author_id = ha.id",
        (AUTHOR,),
    )
    cur.execute(
        "DELETE FROM hivemind_app.hive_posts hp USING hivemind_app.hive_accounts ha "
        "WHERE ha.name = %s AND hp.author_id = ha.id",
        (AUTHOR,),
    )
    cur.execute("DELETE FROM hivemind_app.hive_permlink_data WHERE permlink = ANY(%s)", (list(PERMLINKS),))
    cur.execute("DELETE FROM hivemind_app.hive_category_data WHERE category = %s", (CATEGORY,))
    cur.execute("DELETE FROM hivemind_app.hive_accounts WHERE name = %s", (AUTHOR,))


def main(url: str) -> int:
    conn = _connect(url, 'main')
    cur = conn.cursor()
    _clean(cur)
    try:
        posts = _seed(cur)
        check_order(url, cur, posts, 'posts phase', _posts_phase)
        check_order(url, cur, posts, 'community post ops', _community_post_ops)
        check_order(url, cur, posts, 'payouts', _payouts)
        check_order(url, cur, posts, 'rshares update', _rshares(posts))
        check_overlap(url, cur, posts, 'payouts', _payouts)
        check_overlap(url, cur, posts, 'rshares update', _rshares(posts))
        check_overlap(url, cur, posts, 'payout partitions', _payout_partitions)
    except AssertionError as err:
        print(f"stage lock order check failed: {err}")
        return 1
    finally:
        _clean(cur)
        conn.close()
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1]))
