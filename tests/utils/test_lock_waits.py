"""The lock wait sampler: seconds each hivemind connection waits on locks, from pg_stat_activity samples."""

import threading
from typing import Any
from unittest.mock import MagicMock

import psycopg2
import pytest

from hive.indexer.lock_waits import LockWaitSampler, connection_name


class _Activity:
    """Stands in for the sampler's connection: answers each sample with the next list of waiting connections."""

    def __init__(self, *samples: list[str] | Exception) -> None:
        self._samples = list(samples)
        self.done = threading.Event()
        self.closed = False

    def query_col(self, sql: str) -> list[str]:
        assert "wait_event_type = 'Lock'" in sql
        if not self._samples:
            self.done.set()
            return []
        sample = self._samples.pop(0)
        if isinstance(sample, Exception):
            self.done.set()
            raise sample
        return sample

    def close(self) -> None:
        self.closed = True


def _sampled(activity: _Activity) -> LockWaitSampler:
    db: Any = activity
    sampler = LockWaitSampler(db, interval=0.01)
    sampler.start()
    assert activity.done.wait(5), 'the sampler never took its samples'
    sampler.stop()
    return sampler


def test_each_sample_adds_its_interval_to_the_connections_it_finds_waiting() -> None:
    activity = _Activity(['hivemind_Payouts', 'hivemind_Payouts_1'], ['hivemind_Payouts_1'], [])

    sampler = _sampled(activity)

    one = sampler.total(['hivemind_Payouts'])
    both = sampler.total(['hivemind_Payouts', 'hivemind_Payouts_1'])
    assert 0.0 < one < both, 'a connection waiting in more samples waited longer'
    assert sampler.total(['hivemind_Payouts_1', 'hivemind_Payouts_1']) == pytest.approx(both - one), (
        'a name is counted once'
    )
    assert sampler.total(['hivemind_Follow']) == 0.0, 'a connection never seen waiting waited for nothing'
    assert activity.closed


def test_a_failed_sample_stops_the_sampling_and_keeps_the_totals(caplog: pytest.LogCaptureFixture) -> None:
    activity = _Activity(['hivemind_Reblog'], psycopg2.OperationalError('connection lost'))

    sampler = _sampled(activity)

    assert sampler.total(['hivemind_Reblog']) > 0.0
    assert 'Lock wait sampling stopped' in caplog.text


def test_a_connection_is_named_as_it_connects() -> None:
    db: Any = MagicMock()
    db.name = 'Payouts_2'
    assert connection_name(db) == 'hivemind_Payouts_2'
