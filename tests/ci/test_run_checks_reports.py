import os
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


# A tavern step stand-in: writes a report failing another test, then exits with $FAKE_TAVERN_RC.
_FAKE_TAVERN = '''import os, sys
with open(os.path.join(sys.argv[1], 'tavern-g.xml'), 'w') as report:
    report.write('<testsuite><testcase classname="g.other.tavern.yaml" name="Hivemind"><failure/></testcase></testsuite>')
print('fake tavern step')
sys.exit(int(os.environ['FAKE_TAVERN_RC']))
'''
_FIND_TEXT_ID = 'search-api_patterns.find_text.nyunya_punctuation_relevance.tavern.yaml::Hivemind'


def _fake_tavern(tree: Path, monkeypatch: pytest.MonkeyPatch, rc: int) -> None:
    (tree / '.aidev' / 'hivemind_tavern.py').write_text(_FAKE_TAVERN)
    monkeypatch.setenv('FAKE_TAVERN_RC', str(rc))


def _xml_reports(out: Path) -> list[Path]:
    return sorted(out.rglob('*.xml'))


def test_a_rerun_of_the_real_tavern_step_without_a_provider_leaves_no_report(
    tree: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    for name in ('hivemind_tavern.py', 'hivemind_smoke.py', 'hivemind_rewriter.py'):
        shutil.copy(AIDEV / name, tree / '.aidev' / name)
    (tree / '.aidev' / 'shared-hivemind').mkdir()
    shutil.copy(AIDEV / 'shared-hivemind' / 'shared_fixture.py', tree / '.aidev' / 'shared-hivemind')
    for name in [name for name in os.environ if name.startswith('AIDEV_EXTERNAL_HIVEMIND_')]:
        monkeypatch.delenv(name)

    proc = _run(tree, 'full', 'tavern', '--rerun', _FIND_TEXT_ID)

    assert proc.returncode != 0
    rerun = tree / 'test-results' / 'full' / 'rerun' / '1'
    assert _xml_reports(rerun) == []
    assert _cases(rerun / 'junit.xml.no-verdict')['tavern'][0] in ('failure', 'skipped')


@pytest.mark.parametrize('rc', [2, 77])
def test_a_rerun_whose_step_reached_no_verdict_keeps_no_report_naming_other_tests(
    tree: Path, monkeypatch: pytest.MonkeyPatch, rc: int
) -> None:
    _fake_tavern(tree, monkeypatch, rc)

    proc = _run(tree, 'full', 'tavern', '--rerun', _FIND_TEXT_ID)

    assert proc.returncode == 1
    rerun = tree / 'test-results' / 'full' / 'rerun' / '1'
    assert _xml_reports(rerun) == []
    assert _cases(rerun / 'tavern-g.xml.no-verdict') == {'Hivemind': ('failure', '')}
    assert _cases(rerun / 'junit.xml.no-verdict')['tavern'][0] == ('failure' if rc == 2 else 'skipped')


def test_a_rerun_whose_failures_are_recorded_per_test_keeps_its_reports(
    tree: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    _fake_tavern(tree, monkeypatch, 1)

    proc = _run(tree, 'full', 'tavern', '--rerun', _FIND_TEXT_ID)

    assert proc.returncode == 1
    rerun = tree / 'test-results' / 'full' / 'rerun' / '1'
    assert _xml_reports(rerun) == [rerun / 'junit.xml', rerun / 'tavern-g.xml']
    assert _cases(rerun / 'junit.xml')['tavern'][0] == 'skipped'


@pytest.mark.parametrize(('rc', 'outcome'), [(1, 'skipped'), (2, 'failure')])
def test_the_tavern_step_case_is_demoted_only_when_it_exits_1(
    tree: Path, monkeypatch: pytest.MonkeyPatch, rc: int, outcome: str
) -> None:
    _fake_tavern(tree, monkeypatch, rc)

    proc = _run(tree, 'full', 'tavern')

    assert proc.returncode == 1
    out = tree / 'test-results' / 'full'
    assert _cases(out / 'junit.xml')['tavern'][0] == outcome
    assert _cases(out / 'tavern-g.xml') == {'Hivemind': ('failure', '')}
