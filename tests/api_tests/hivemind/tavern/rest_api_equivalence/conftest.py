"""Parametrizes the REST equivalence tests over the JSON-RPC tavern tests, read at collection."""

import pytest
from rest_checks import service
from rest_checks.equivalence import TAVERN_DIR, DerivedCase, coverage, derive_cases

_CASES = derive_cases(TAVERN_DIR)


def _marks(case: DerivedCase) -> list[pytest.MarkDecorator]:
    marks = []
    for name in case.marks:
        if name == "xfail":
            marks.append(pytest.mark.xfail(reason=f"{case.source} is marked xfail"))
        else:
            marks.append(getattr(pytest.mark, name))
    search_skip = service.search_skip_reason() if case.mapping.method.startswith("search-api.") else None
    if case.skip_reason is not None:
        marks.append(pytest.mark.skip(reason=case.skip_reason))
    elif search_skip is not None:
        marks.append(pytest.mark.skip(reason=search_skip))
    return marks


def pytest_generate_tests(metafunc: pytest.Metafunc) -> None:
    if "derived_case" in metafunc.fixturenames:
        metafunc.parametrize(
            "derived_case", [pytest.param(case, id=case.source, marks=_marks(case)) for case in _CASES]
        )


def pytest_terminal_summary(terminalreporter: pytest.TerminalReporter) -> None:
    terminalreporter.section("REST tests derived from JSON-RPC tests, per endpoint")
    for line in coverage(_CASES):
        terminalreporter.write_line(line)
