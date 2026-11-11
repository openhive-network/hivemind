"""Every end of the hive process logs its reason and exit code, when the main thread ends and when the process does."""

import logging
from collections.abc import Callable
from unittest.mock import MagicMock, patch

import pytest

from hive import cli


def _run(run_body: Callable[[], None]) -> MagicMock:
    at_exit: list[Callable[[], None]] = []
    enable = MagicMock()
    with (
        patch.object(cli, '_run', run_body),
        patch('atexit.register', at_exit.append),
        patch('faulthandler.enable', enable),
    ):
        try:
            cli.run()
        finally:
            for handler in at_exit:
                handler()
    return enable


def _messages(caplog: pytest.LogCaptureFixture) -> list[tuple[int, str]]:
    return [(r.levelno, r.getMessage()) for r in caplog.records if r.name == 'hive.cli']


def _raise(exc: BaseException) -> Callable[[], None]:
    def body() -> None:
        raise exc

    return body


def test_normal_end_logs_code_zero(caplog: pytest.LogCaptureFixture) -> None:
    caplog.set_level(logging.INFO)
    enable = _run(lambda: None)
    enable.assert_called_once_with()
    messages = _messages(caplog)
    assert messages[0] == (logging.INFO, 'Main thread ended (finished); exit code 0')
    assert messages[1][0] == logging.INFO
    assert messages[1][1].startswith('Process exiting with code 0, ')
    assert messages[1][1].endswith('after the main thread ended (finished)')
    assert len(messages) == 2


def test_exception_logs_its_reason_and_code_one(caplog: pytest.LogCaptureFixture) -> None:
    with pytest.raises(RuntimeError, match='missing chunk'):
        _run(_raise(RuntimeError('missing chunk number 0')))
    messages = _messages(caplog)
    assert messages[0] == (logging.ERROR, 'Main thread ended (RuntimeError: missing chunk number 0); exit code 1')
    assert messages[1][0] == logging.ERROR
    assert messages[1][1].startswith('Process exiting with code 1, ')
    assert messages[1][1].endswith('(RuntimeError: missing chunk number 0)')


@pytest.mark.parametrize(
    ('code', 'expected', 'level'),
    [(0, 0, logging.INFO), (None, 0, logging.INFO), (3, 3, logging.ERROR), ('fatal', 1, logging.ERROR)],
)
def test_system_exit_logs_its_code(
    caplog: pytest.LogCaptureFixture, code: int | str | None, expected: int, level: int
) -> None:
    caplog.set_level(logging.INFO)
    with pytest.raises(SystemExit):
        _run(_raise(SystemExit(code)))
    assert _messages(caplog)[0] == (level, f'Main thread ended (SystemExit({code!r})); exit code {expected}')


def test_keyboard_interrupt_logs_the_sigint_code(caplog: pytest.LogCaptureFixture) -> None:
    with pytest.raises(KeyboardInterrupt):
        _run(_raise(KeyboardInterrupt()))
    assert _messages(caplog)[0] == (logging.ERROR, 'Main thread ended (KeyboardInterrupt); exit code 130')
