"""A massive batch's posts phase: applied once, and reused by a replay of the batch once it has committed."""

from typing import Any
from unittest.mock import MagicMock

import pytest

from hive.indexer.blocks import Blocks

_PROCESS = 'process_posts_from_staging('
_SAVE = 'SELECT hivemind_app.save_batch_post_results()'
_RESTORE = 'SELECT * FROM hivemind_app.restore_batch_post_results()'


def _run(markers: dict[str, bool] | None) -> tuple[list[str], tuple[list[Any], bool]]:
    """The statements the posts phase sends, and what it returns, with _batch_queue holding `markers`."""
    statements: list[str] = []
    db = MagicMock()
    db.query_no_return.side_effect = statements.append
    rows = [MagicMock(name='row')]

    def query_all(sql: str) -> list[Any]:
        statements.append(sql)
        if '_batch_queue' in sql:
            return [] if markers is None else [MagicMock(_mapping=markers)]
        return rows

    db.query_all.side_effect = query_all
    result = Blocks._process_batch_posts(db)
    assert result[0] is rows
    return statements, result


@pytest.mark.parametrize('markers', [None, {'posts_applied': False, 'post_data_applied': False}])
def test_a_first_run_applies_the_posts_and_saves_their_results_in_the_same_transaction(
    markers: dict[str, bool] | None,
) -> None:
    statements, (_, post_data_applied) = _run(markers)

    assert statements[0] == 'START TRANSACTION'
    assert _PROCESS in statements[2]
    assert statements[3:] == [_SAVE, 'COMMIT']
    assert not any(_RESTORE in s for s in statements)
    assert post_data_applied is False


@pytest.mark.parametrize('post_data_applied', [False, True])
def test_a_replay_after_the_posts_phase_committed_reuses_its_results(post_data_applied: bool) -> None:
    statements, (_, reported) = _run({'posts_applied': True, 'post_data_applied': post_data_applied})

    assert statements[0] == 'START TRANSACTION'
    assert statements[2:] == [_RESTORE, 'COMMIT']
    assert not any(_PROCESS in s or _SAVE in s for s in statements)
    assert reported is post_data_applied
