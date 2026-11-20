"""Private-interface tests for hive.db.schema internals."""

import logging
from unittest.mock import MagicMock

import psycopg2.errors
import pytest

from hive.db.schema import _try_create_extension


def test_failed_create_extension_logs_the_first_line_of_the_error(caplog: pytest.LogCaptureFixture) -> None:
    db = MagicMock()
    db.query.side_effect = psycopg2.errors.FeatureNotSupported(
        'pg_search must be loaded via shared_preload_libraries\nCONTEXT:  SQL statement "LOAD"'
    )

    with caplog.at_level(logging.WARNING, logger='hive.db.schema'):
        assert _try_create_extension(db, 'pg_search') is False

    messages = [r.getMessage() for r in caplog.records if r.levelno == logging.WARNING]
    assert messages == ['Could not create extension pg_search: pg_search must be loaded via shared_preload_libraries']
