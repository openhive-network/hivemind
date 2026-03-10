"""Tests for hive.db.adapter.Row equality and hashing."""

from hive.db.adapter import Row


def test_equal_rows():
    r1 = Row(('alice', 1), ('name', 'id'))
    r2 = Row(('alice', 1), ('name', 'id'))
    assert r1 == r2


def test_different_data():
    r1 = Row(('alice', 1), ('name', 'id'))
    r2 = Row(('bob', 2), ('name', 'id'))
    assert r1 != r2


def test_different_columns():
    r1 = Row(('alice',), ('name',))
    r2 = Row(('alice',), ('username',))
    assert r1 != r2


def test_not_equal_to_non_row():
    r = Row(('alice',), ('name',))
    assert r != 'alice'
    assert r != ('alice',)
    assert r != 42


def test_hash_equal_rows():
    r1 = Row(('alice', 1), ('name', 'id'))
    r2 = Row(('alice', 1), ('name', 'id'))
    assert hash(r1) == hash(r2)


def test_hash_different_rows():
    r1 = Row(('alice',), ('name',))
    r2 = Row(('bob',), ('name',))
    assert hash(r1) != hash(r2)


def test_set_deduplication():
    rows = [
        Row(('alice',), ('name',)),
        Row(('alice',), ('name',)),
        Row(('bob',), ('name',)),
    ]
    assert len(set(rows)) == 2


def test_set_equality():
    """Mirrors the actual usage in sync.py for connection tracking."""
    before = [
        Row(('hivemind',), ('application_name',)),
        Row(('rep_tracker',), ('application_name',)),
    ]
    after = [
        Row(('rep_tracker',), ('application_name',)),
        Row(('hivemind',), ('application_name',)),
    ]
    assert set(before) == set(after)


def test_set_inequality():
    before = [
        Row(('hivemind',), ('application_name',)),
        Row(('rep_tracker',), ('application_name',)),
    ]
    after = [
        Row(('hivemind',), ('application_name',)),
    ]
    assert set(before) != set(after)


def test_list_input_from_psycopg2():
    """psycopg2 fetchall() returns lists, not tuples. Row must handle both."""
    r1 = Row(['alice', 1], ['name', 'id'])
    r2 = Row(('alice', 1), ('name', 'id'))
    assert r1 == r2
    assert hash(r1) == hash(r2)
    assert len({r1, r2}) == 1
