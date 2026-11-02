import shutil
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
AIDEV = ROOT / '.aidev'

_UNIT_TESTS = '''
def test_passes():
    pass


def test_fails():
    assert False
'''


@pytest.fixture
def tree(tmp_path: Path) -> Path:
    """A scratch checkout holding the wrapper and a unit test module, so its reports land outside the repository."""
    root = tmp_path / 'tree'
    (root / '.aidev').mkdir(parents=True)
    for name in ('run-checks.sh', 'junit_cases.py'):
        shutil.copy(AIDEV / name, root / '.aidev' / name)
    (root / 'hive').mkdir()
    (root / 'tests' / 'utils').mkdir(parents=True)
    (root / 'tests' / 'utils' / 'test_sample.py').write_text(_UNIT_TESTS)
    return root


def _run(tree: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ['bash', str(tree / '.aidev' / 'run-checks.sh'), *args], capture_output=True, text=True, timeout=120
    )


def _cases(junit: Path) -> dict[str, tuple[str, str]]:
    """Each case of `junit` by name: its outcome and message."""
    cases = {}
    for case in ET.parse(junit).getroot().iter('testcase'):
        outcome = next((child for child in case if child.tag in ('failure', 'error', 'skipped')), None)
        cases[case.get('name', '')] = (
            outcome.tag if outcome is not None else 'pass',
            outcome.get('message', '') if outcome is not None else '',
        )
    return cases


def test_a_failure_the_unit_report_records_is_not_reported_again_as_the_step(tree: Path) -> None:
    proc = _run(tree, 'quick', 'unit')

    assert proc.returncode == 1
    out = tree / 'test-results' / 'quick'
    outcome, message = _cases(out / 'junit.xml')['unit']
    assert outcome == 'skipped'
    assert message == 'exit 1: 1 failing test(s) reported per test in unit.xml'
    assert _cases(out / 'unit.xml') == {'test_passes': ('pass', ''), 'test_fails': ('failure', 'assert False')}


def test_a_step_that_crashes_fails_as_itself_even_when_its_report_records_an_error(tree: Path) -> None:
    (tree / 'tests' / 'utils' / 'test_broken.py').write_text('def test_x(:\n')

    proc = _run(tree, 'quick', 'unit')

    assert proc.returncode == 1
    out = tree / 'test-results' / 'quick'
    assert any(outcome == 'error' for outcome, _ in _cases(out / 'unit.xml').values())
    assert _cases(out / 'junit.xml')['unit'][0] == 'failure'


def test_a_rerun_runs_only_the_named_test_and_keeps_the_run_it_re_runs(tree: Path) -> None:
    assert _run(tree, 'quick', 'unit', 'ruff').returncode == 1

    proc = _run(tree, 'quick', 'unit', 'ruff', '--rerun', 'tests/utils/test_sample.py::test_passes')

    assert proc.returncode == 0
    out = tree / 'test-results' / 'quick'
    assert _cases(out / 'rerun' / '1' / 'junit.xml') == {'unit': ('pass', '')}
    assert _cases(out / 'rerun' / '1' / 'unit.xml') == {'test_passes': ('pass', '')}
    assert 'unit' in _cases(out / 'junit.xml') and 'ruff' in _cases(out / 'junit.xml')
    assert _run(tree, 'quick', 'unit', '--rerun', 'tests/utils/test_sample.py::test_fails').returncode == 1
    assert _cases(out / 'rerun' / '2' / 'unit.xml') == {'test_fails': ('failure', 'assert False')}


def test_a_rerun_of_an_id_no_listed_step_runs_fails(tree: Path) -> None:
    proc = _run(tree, 'quick', 'unit', '--rerun', 'search-api_patterns.find_text.x.tavern.yaml::Hivemind')

    assert proc.returncode == 1
    outcome, message = _cases(tree / 'test-results' / 'quick' / 'rerun' / '1' / 'junit.xml')['rerun-ids']
    assert outcome == 'failure'
    assert message == 're-run ids no listed step runs: search-api_patterns.find_text.x.tavern.yaml::Hivemind'


@pytest.mark.parametrize('args', [['--rerun'], ['--rerun', '-p', 'x'], ['bogus']])
def test_a_malformed_invocation_is_refused_before_any_step(tree: Path, args: list[str]) -> None:
    proc = _run(tree, 'quick', 'unit', *args)

    assert proc.returncode == 2
    assert not (tree / 'test-results').exists()
