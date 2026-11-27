"""Guard the parallel post-sync finalization against the serial one, on a synced database.

On a disposable copy of a synced hivemind (the tavern step's clone of the shared
fixture: HAF 5M + CI's mocks + a hivemind sync), named by HIVEMIND_FINALIZATION_DB_URL,
the finalization's inputs are first put back into the state a massive sync leaves
them in: hive_votes in insertion order without its ordering mark, the posts' vote
aggregates and `children` stale, no feed cache, no vote notifications and no BM25
index, and the post data of a last massive batch not yet written (the newest
top-level posts missing, some older ones with a stale body). From that state the
finalization runs:

- serial, as before the split: the batch, CLUSTER of hive_votes on its order
  index, then recalculate_all_posts_votes_and_children (one range, one
  connection), then the BM25 build;
- parallel, as DbState runs it now (finalization_workers = 4), from each entry
  into the index phase: the index phase every entry runs
  (ensure_indexes_are_enabled with hive_posts' indexes deferred and the BM25
  build), which rewrites hive_votes in post order beside the BM25 build, then the
  recompute over post id ranges on several connections. Entered from live or at
  --test-max-block, the batch comes before the index phase; entered from
  MASSIVE_WITH_INDEXES, after it, so the BM25 index takes its writes.

Both then fill the feed cache and the notifications (clear_muted_notifications,
the vote notification flush, the reputation scores) with the same code, and the
parallel result must equal the serial one: every hive_posts row, every hive_votes
row stored in (post_id, voter_id) order with the order index marked as the
clustering one, hive_feed_cache, hive_notification_cache (on everything but the
drawn id), and the same valid indexes, BM25 included when pg_search is installed,
finding the same posts for the batch's new and replaced bodies.

Planted defects show that the comparison sees what it guards: the recompute with
one of its ranges dropped leaves exactly that range's stale posts different, the
rewrite without its ordering mark is reported as unmarked, and a range applied
twice changes nothing, since the recompute writes absolute values, not deltas, and
a BM25 index that missed the batch's writes finds other posts.

Unlike a real initial sync, hive_votes and hive_posts keep their indexes through
the run (CLUSTER rebuilds hive_votes' own). Without HIVEMIND_FINALIZATION_DB_URL
every test is skipped.

  HIVEMIND_FINALIZATION_DB_URL=postgresql://hivemind@<host>/<clone> \\
      python3 -m pytest tests/finalization/test_finalization_equality.py
"""

from __future__ import annotations

import os
from collections.abc import Iterator
from pathlib import Path
from typing import Any
from unittest.mock import patch

import psycopg2
import psycopg2.extensions
import pytest

import hive.db.schema as schema_module
from hive.db.adapter import Db
from hive.db.db_state import DbState
from hive.db.schema import bm25_index_sql

_URL_VARIABLE = 'HIVEMIND_FINALIZATION_DB_URL'
_URL = os.environ.get(_URL_VARIABLE)

pytestmark = pytest.mark.skipif(not _URL, reason=f'{_URL_VARIABLE} names no disposable synced hivemind database')

_SQL_SCRIPTS = Path(__file__).resolve().parents[2] / 'hive' / 'db' / 'sql_scripts'
# The SQL of the pieces under test, loaded from this tree in case the clone was synced by another one.
_FINALIZATION_SCRIPTS = ('update_posts_rshares.sql',)
_WORKERS = 4
_ORDER_INDEX = 'hive_votes_post_id_voter_id_idx'
_BM25_INDEX = 'hive_post_data_bm25_idx'
_RECOMPUTED_COLUMNS = ('children', 'abs_rshares', 'vote_rshares', 'total_votes', 'net_votes', 'sc_hot', 'sc_trend')
_RECOMPUTED = ', '.join(_RECOMPUTED_COLUMNS)
# The new top-level posts, and the older ones edited, of the last massive batch.
_BATCH_POSTS = 20
# A word no post has: the body the batch's edited posts had before it.
_STALE_BODY = 'festalebodymarker'
# Each compared table and the row it is compared on.
_TABLES = {
    'hive_posts': 'to_jsonb(t)',
    'hive_votes': 'to_jsonb(t)',
    'hive_feed_cache': 'to_jsonb(t)',
    'hive_notification_cache': "to_jsonb(t) - 'id'",
}
_INDEXES = """
SELECT pg_get_indexdef(i.indexrelid) AS definition
FROM pg_index i
JOIN pg_class c ON c.oid = i.indrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'hivemind_app'
"""


def _row(alias: str) -> str:
    """The recomputed columns of `alias`, as a row."""
    return '(' + ', '.join(f'{alias}.{column}' for column in _RECOMPUTED_COLUMNS) + ')'


class _MarkerDroppingDb(Db):
    """A connection, and its clones, that clear the clustering mark CLUSTER sets on hive_votes' order index."""

    def clone(self, name: str) -> Db:
        return _MarkerDroppingDb(self._url, name)

    def query_no_return(self, sql: str, **kwargs: Any) -> None:
        super().query_no_return(sql, **kwargs)
        if sql.startswith('CLUSTER '):
            super().query_no_return('ALTER TABLE hivemind_app.hive_votes SET WITHOUT CLUSTER')


class _Finalization:
    """The database under test, its pre-finalization state saved in temporary tables of `conn`."""

    def __init__(self, url: str) -> None:
        self.url = url
        self.conn = psycopg2.connect(url, application_name='finalization_equality')
        self.conn.autocommit = True
        self.db = Db(url, 'finalization_equality')
        self.search = bool(self.one("SELECT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_search')"))
        self.serial_hits: dict[str, list[int]] = {}

    def run(self, sql: str) -> None:
        with self.conn.cursor() as cur:
            cur.execute(sql)

    def one(self, sql: str) -> Any:
        with self.conn.cursor() as cur:
            cur.execute(sql)
            row = cur.fetchone()
        if row is None:
            raise AssertionError(f'no row from {sql}')
        return row[0]

    def column(self, sql: str) -> list[Any]:
        with self.conn.cursor() as cur:
            cur.execute(sql)
            return [row[0] for row in cur.fetchall()]

    def make_pre_finalization_state(self) -> None:
        """Bring the finalization's inputs to the state massive sync leaves, and save it."""
        self.run('CREATE TEMP TABLE fe_votes_unordered AS SELECT * FROM hivemind_app.hive_votes ORDER BY id')
        self.restore_votes()
        self.run(
            f"""
            UPDATE hivemind_app.hive_posts hp
            SET children = 0,
                abs_rshares = CASE WHEN v.voted THEN 0 ELSE hp.abs_rshares END,
                vote_rshares = CASE WHEN v.voted THEN 0 ELSE hp.vote_rshares END,
                total_votes = CASE WHEN v.voted THEN 0 ELSE hp.total_votes END,
                net_votes = CASE WHEN v.voted THEN 0 ELSE hp.net_votes END,
                sc_hot = CASE WHEN v.voted THEN 0 ELSE hp.sc_hot END,
                sc_trend = CASE WHEN v.voted THEN 0 ELSE hp.sc_trend END
            FROM (
                SELECT p.id, EXISTS (SELECT 1 FROM hivemind_app.hive_votes hv WHERE hv.post_id = p.id) AS voted
                FROM hivemind_app.hive_posts p
            ) v
            WHERE v.id = hp.id
            AND (hp.children != 0 OR (v.voted AND ({_RECOMPUTED}) IS DISTINCT FROM (0, 0, 0, 0, 0, 0, 0)))
            """
        )
        self.run('DELETE FROM hivemind_app.hive_notification_cache WHERE type_id = 17')
        self.run(f'CREATE TEMP TABLE fe_pre_posts AS SELECT id, {_RECOMPUTED} FROM hivemind_app.hive_posts')
        self.run('CREATE TEMP TABLE fe_pre_notifications AS SELECT * FROM hivemind_app.hive_notification_cache')
        self.run(
            f"""
            CREATE TEMP TABLE fe_batch_post_data AS
            (SELECT hpd.*, TRUE AS new FROM hivemind_app.hive_post_data hpd
             JOIN hivemind_app.hive_posts hp ON hp.id = hpd.id
             WHERE hp.depth = 0 AND hp.id > 0 ORDER BY hpd.id DESC LIMIT {_BATCH_POSTS})
            UNION ALL
            (SELECT hpd.*, FALSE FROM hivemind_app.hive_post_data hpd
             JOIN hivemind_app.hive_posts hp ON hp.id = hpd.id
             WHERE hp.depth = 0 AND hp.id > 0 ORDER BY hpd.id LIMIT {_BATCH_POSTS})
            """
        )
        if self.one('SELECT count(DISTINCT id) FROM fe_batch_post_data') != 2 * _BATCH_POSTS:
            raise AssertionError(f'the clone has fewer than {2 * _BATCH_POSTS} top-level posts with post data')
        self.restore_post_data()
        self.restore_outputs()

    def restore_votes(self) -> None:
        """hive_votes in the saved order, its order index unmarked."""
        self.run('ALTER TABLE hivemind_app.hive_votes SET WITHOUT CLUSTER')
        self.run('TRUNCATE TABLE hivemind_app.hive_votes')
        self.run('INSERT INTO hivemind_app.hive_votes SELECT * FROM fe_votes_unordered ORDER BY id')

    def restore_posts(self) -> None:
        self.run(
            f"""
            UPDATE hivemind_app.hive_posts hp SET ({_RECOMPUTED}) = {_row('p')}
            FROM fe_pre_posts p
            WHERE p.id = hp.id AND {_row('hp')} IS DISTINCT FROM {_row('p')}
            """
        )

    def restore_post_data(self) -> None:
        """hive_post_data as before the batch: its new posts missing, its edited ones with the stale body."""
        self.run('DELETE FROM hivemind_app.hive_post_data WHERE id IN (SELECT id FROM fe_batch_post_data WHERE new)')
        self.run(
            f"""
            UPDATE hivemind_app.hive_post_data SET body = '{_STALE_BODY}'
            WHERE id IN (SELECT id FROM fe_batch_post_data WHERE NOT new)
            """
        )

    def write_batch(self) -> None:
        """The batch's post data flush: its new posts inserted, its edited ones given their body."""
        self.run(
            """
            INSERT INTO hivemind_app.hive_post_data (id, title, body, json)
            SELECT id, title, body, json FROM fe_batch_post_data WHERE new
            """
        )
        self.run(
            """
            UPDATE hivemind_app.hive_post_data hpd SET body = b.body
            FROM fe_batch_post_data b
            WHERE b.id = hpd.id AND NOT b.new
            """
        )

    def restore_outputs(self) -> None:
        """No feed cache, the saved notifications and no BM25 index."""
        self.run('TRUNCATE TABLE hivemind_app.hive_feed_cache')
        self.run('DELETE FROM hivemind_app.hive_notification_cache')
        self.run('INSERT INTO hivemind_app.hive_notification_cache SELECT * FROM fe_pre_notifications')
        self.run(f'DROP INDEX IF EXISTS hivemind_app.{_BM25_INDEX}')

    def restore(self) -> None:
        self.restore_votes()
        self.restore_posts()
        self.restore_outputs()
        self.restore_post_data()

    def fill_outputs(self) -> None:
        """The finalization steps both arms share: feed cache and notifications."""
        head = self.one("SELECT hive.app_get_current_block_num('hivemind_app')")
        DbState._finish_hive_feed_cache(self.db, 0, head)
        DbState._finish_notification_cache(self.db)
        DbState._finish_vote_notifications(self.db)
        DbState._finish_reputation_notification_scores(self.db)

    def run_serial(self) -> None:
        self.write_batch()
        self.run(f'CLUSTER hivemind_app.hive_votes USING {_ORDER_INDEX}')
        self.run('SELECT hivemind_app.recalculate_all_posts_votes_and_children()')
        if self.search:
            self.run(bm25_index_sql())
        self.fill_outputs()

    def run_parallel(self, batch_after_index_phase: bool) -> None:
        with self.initial_sync():
            if not batch_after_index_phase:
                self.write_batch()
            self.run_index_phase()
            if batch_after_index_phase:
                self.write_batch()
            DbState._recalculate_all_posts_votes_and_children(self.db)
            DbState._restore_deferred_indexes()
        self.fill_outputs()

    @staticmethod
    def initial_sync() -> Any:
        """DbState as an initial sync leaving MASSIVE_WITHOUT_INDEXES finds it."""
        return patch.multiple(
            DbState,
            _initial_sync=True,
            _indexes_were_enabled=False,
            _indexes_were_disabled=True,
            _deferred_index_tables=[],
        )

    @staticmethod
    def run_index_phase() -> None:
        """The index phase, as every entry into it from MASSIVE_WITHOUT_INDEXES runs it (hive/indexer/sync.py)."""
        DbState.ensure_indexes_are_enabled(defer_to_finalization=True, build_search_index=True)

    def save_serial(self) -> None:
        for table, row in _TABLES.items():
            self.run(f'CREATE TEMP TABLE fe_serial_{table} AS SELECT {row} AS r FROM hivemind_app.{table} t')
        self.run(f'CREATE TEMP TABLE fe_serial_posts AS SELECT id, {_RECOMPUTED} FROM hivemind_app.hive_posts')
        self.run(f'CREATE TEMP TABLE fe_serial_indexes AS {_INDEXES}')
        self.serial_hits = self.search_hits()

    def search_hits(self) -> dict[str, list[int]]:
        """The top-level posts the BM25 index finds for the batch's replaced bodies and for its new posts' ids."""
        if not self.search:
            return {}
        newest = self.one('SELECT min(id) FROM fe_batch_post_data WHERE new')
        searches = {
            'stale body': f"paradedb.parse('body:{_STALE_BODY}')",
            'newest posts': f"paradedb.range('id', int4range({newest}, NULL))",
        }
        return {
            name: self.one(
                f"""
                SELECT COALESCE(array_agg(s.id ORDER BY s.id), '{{}}') FROM (
                    SELECT hpd.id FROM hivemind_app.hive_post_data hpd
                    WHERE hpd @@@ {query} AND hivemind_app.is_top_level_post(hpd.id)
                ) s
                """
            )
            for name, query in searches.items()
        }

    def differing_rows(self, table: str) -> int:
        """The rows of `table` the serial result lacks, plus those of the serial result `table` lacks."""
        live = f'SELECT {_TABLES[table]} AS r FROM hivemind_app.{table} t'
        return int(
            self.one(
                f"""
                SELECT count(*) FROM (
                    ({live} EXCEPT ALL SELECT r FROM fe_serial_{table})
                    UNION ALL
                    (SELECT r FROM fe_serial_{table} EXCEPT ALL {live})
                ) d
                """
            )
        )

    def votes_order_problems(self) -> dict[str, Any]:
        problems: dict[str, Any] = {}
        inverted = self.one(
            """
            SELECT count(*) FROM (
                SELECT (post_id, voter_id) < lag((post_id, voter_id)) OVER (ORDER BY ctid) AS inverted
                FROM hivemind_app.hive_votes
            ) o WHERE o.inverted
            """
        )
        if inverted:
            problems['hive_votes rows following a greater (post_id, voter_id)'] = inverted
        if not self.one(
            f"SELECT indisclustered FROM pg_index WHERE indexrelid = 'hivemind_app.{_ORDER_INDEX}'::regclass"
        ):
            problems['ordering mark'] = f'{_ORDER_INDEX} is not marked as the clustering index'
        return problems

    def index_problems(self) -> dict[str, Any]:
        problems: dict[str, Any] = {}
        invalid = self.column(
            """
            SELECT i.indexrelid::regclass::text
            FROM pg_index i
            JOIN pg_class c ON c.oid = i.indrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'hivemind_app' AND NOT (i.indisvalid AND i.indisready)
            """
        )
        if invalid:
            problems['invalid indexes'] = invalid
        changed = self.column(
            f"""
            (({_INDEXES}) EXCEPT SELECT definition FROM fe_serial_indexes)
            UNION ALL
            (SELECT definition FROM fe_serial_indexes EXCEPT ({_INDEXES}))
            """
        )
        if changed:
            problems['indexes unlike the serial run'] = changed
        if self.search and not self.one(f"SELECT to_regclass('hivemind_app.{_BM25_INDEX}') IS NOT NULL"):
            problems['BM25 index'] = f'{_BM25_INDEX} was not built'
            return problems
        hits = self.search_hits()
        if hits != self.serial_hits:
            problems['BM25 hits unlike the serial run'] = {'serial': self.serial_hits, 'this run': hits}
        return problems

    def differences(self) -> dict[str, Any]:
        """Everything the result differs in from the serial one, by what differs."""
        problems: dict[str, Any] = {f'{table} rows': n for table in _TABLES if (n := self.differing_rows(table))}
        return problems | self.votes_order_problems() | self.index_problems()

    def stale_post_ids(self) -> list[int]:
        """The posts whose saved pre-finalization values differ from the serial result's."""
        return self.column(
            f"""
            SELECT p.id FROM fe_pre_posts p JOIN fe_serial_posts s ON s.id = p.id
            WHERE {_row('p')} IS DISTINCT FROM {_row('s')}
            ORDER BY p.id
            """
        )


@pytest.fixture(scope='module')
def finalization() -> Iterator[_Finalization]:
    """The database under test in its pre-finalization state, with the serial finalization's result saved."""
    assert _URL is not None
    fin = _Finalization(_URL)
    saved = (DbState._db, DbState.finalization_workers, Db.max_connections, schema_module.pg_search_available)
    DbState._db = fin.db
    DbState.finalization_workers = _WORKERS
    # The index phase runs its tasks on Db.max_connections threads; the hive_votes task waits
    # for the BM25 one, so they need two at least.
    Db.set_max_connections(fin.db)
    schema_module.pg_search_available = fin.search
    try:
        for script in _FINALIZATION_SCRIPTS:
            fin.db.query_no_return((_SQL_SCRIPTS / script).read_text(encoding='utf-8'))
        fin.make_pre_finalization_state()
        if not fin.votes_order_problems().get('hive_votes rows following a greater (post_id, voter_id)'):
            raise AssertionError(
                'hive_votes is in post order before finalization, so the ordering check measures nothing'
            )
        fin.run_serial()
        fin.save_serial()
        if not fin.stale_post_ids():
            raise AssertionError('no post is stale before finalization, so the recompute check measures nothing')
        problems = fin.votes_order_problems() | fin.index_problems()
        if problems:
            raise AssertionError(f'the serial finalization itself left {problems}')
        new_ids = fin.column('SELECT id FROM fe_batch_post_data WHERE new')
        if fin.search and (fin.serial_hits['stale body'] or not set(new_ids) <= set(fin.serial_hits['newest posts'])):
            raise AssertionError(f'the serial BM25 build does not reflect the batch: {fin.serial_hits}')
        yield fin
    finally:
        DbState._db, DbState.finalization_workers, Db.max_connections, schema_module.pg_search_available = saved
        fin.db.close()
        fin.conn.close()


def _range_holding(post_id: int) -> tuple[int, int]:
    max_id = DbState.db().query_one('SELECT COALESCE(MAX(id), 0) FROM hivemind_app.hive_posts')
    ranges = DbState._post_id_ranges(max_id, DbState.finalization_workers * DbState._RECOMPUTE_RANGES_PER_WORKER)
    return next(r for r in ranges if r[0] <= post_id <= r[1])


@pytest.mark.parametrize(
    'batch_after_index_phase',
    [pytest.param(False, id='from live or test-max-block'), pytest.param(True, id='from MASSIVE_WITH_INDEXES')],
)
def test_the_parallel_finalization_gives_the_serial_ones_data(
    finalization: _Finalization, batch_after_index_phase: bool
) -> None:
    finalization.restore()
    assert finalization.differences(), (
        'the pre-finalization state equals the serial result, so the check measures nothing'
    )

    finalization.run_parallel(batch_after_index_phase)

    assert finalization.differences() == {}


def test_a_bm25_index_that_missed_the_batchs_writes_finds_other_posts(finalization: _Finalization) -> None:
    if not finalization.search:
        pytest.skip('pg_search is not installed, so no BM25 index is built')
    finalization.restore()

    with finalization.initial_sync():
        finalization.run_index_phase()

    hits = finalization.search_hits()
    assert hits['stale body'] == finalization.column('SELECT id FROM fe_batch_post_data WHERE NOT new ORDER BY id')
    assert not set(finalization.column('SELECT id FROM fe_batch_post_data WHERE new')) & set(hits['newest posts'])


def test_a_recompute_with_a_range_dropped_differs_in_exactly_that_ranges_stale_posts(
    finalization: _Finalization, monkeypatch: pytest.MonkeyPatch
) -> None:
    stale = finalization.stale_post_ids()
    dropped = _range_holding(stale[len(stale) // 2])
    split = DbState._post_id_ranges
    monkeypatch.setattr(
        DbState,
        '_post_id_ranges',
        classmethod(lambda cls, max_id, count: [r for r in split(max_id, count) if r != dropped]),
    )
    finalization.restore_posts()

    DbState._recalculate_all_posts_votes_and_children(DbState.db())

    stale_in_dropped = sum(1 for post_id in stale if dropped[0] <= post_id <= dropped[1])
    assert finalization.differing_rows('hive_posts') == 2 * stale_in_dropped


def test_a_recompute_with_a_range_applied_twice_gives_the_serial_ones_posts(
    finalization: _Finalization, monkeypatch: pytest.MonkeyPatch
) -> None:
    stale = finalization.stale_post_ids()
    repeated = _range_holding(stale[len(stale) // 2])
    split = DbState._post_id_ranges
    monkeypatch.setattr(
        DbState, '_post_id_ranges', classmethod(lambda cls, max_id, count: [*split(max_id, count), repeated])
    )
    finalization.restore_posts()
    assert finalization.differing_rows('hive_posts') > 0

    DbState._recalculate_all_posts_votes_and_children(DbState.db())

    assert finalization.differing_rows('hive_posts') == 0


def test_a_rewrite_of_hive_votes_without_its_ordering_mark_is_reported_unmarked(finalization: _Finalization) -> None:
    finalization.restore_votes()
    db = _MarkerDroppingDb(finalization.url, 'finalization_equality_unmarked')
    try:
        DbState._order_hive_votes_by_post(db)
    finally:
        db.close()

    assert finalization.differing_rows('hive_votes') == 0
    assert finalization.votes_order_problems() == {
        'ordering mark': f'{_ORDER_INDEX} is not marked as the clustering index'
    }
