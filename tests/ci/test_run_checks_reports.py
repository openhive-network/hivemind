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


def _names(junit: Path) -> set[str]:
    """The ids `junit`'s cases go by: each case's name, and `<classname>::<name>`."""
    names = set()
    for case in ET.parse(junit).getroot().iter('testcase'):
        names |= {case.get('name', ''), f"{case.get('classname', '')}::{case.get('name', '')}"}
    return names


@pytest.mark.parametrize(
    'missing', ['tests/utils/test_does_not_exist.py::test_x', 'tests/utils/test_sample.py::test_does_not_exist']
)
def test_a_unit_rerun_of_an_id_naming_no_test_of_the_tree_is_a_verdict_of_absent(tree: Path, missing: str) -> None:
    proc = _run(tree, 'quick', 'unit', '--rerun', missing)

    assert proc.returncode == 1
    rerun = tree / 'test-results' / 'quick' / 'rerun' / '1'
    assert _xml_reports(rerun) == [rerun / 'junit.xml']
    outcome, message = _cases(rerun / 'junit.xml')['rerun-absent']
    assert outcome == 'failure'
    assert message == f're-run ids naming no test of this tree: {missing}'
    assert not any(missing.endswith(name) for name in _names(rerun / 'junit.xml'))


def test_a_unit_rerun_still_runs_the_named_tests_beside_one_naming_no_test(tree: Path) -> None:
    proc = _run(
        tree, 'quick', 'unit', '--rerun', 'tests/utils/test_sample.py::test_passes', 'tests/utils/test_gone.py::test_x'
    )

    assert proc.returncode == 1
    rerun = tree / 'test-results' / 'quick' / 'rerun' / '1'
    assert _cases(rerun / 'unit.xml') == {'test_passes': ('pass', '')}
    assert _cases(rerun / 'junit.xml') == {
        'unit': ('pass', ''),
        'rerun-absent': ('failure', 're-run ids naming no test of this tree: tests/utils/test_gone.py::test_x'),
    }


def test_a_unit_rerun_whose_collection_fails_still_reaches_no_verdict(tree: Path) -> None:
    (tree / 'tests' / 'utils' / 'test_broken.py').write_text('def test_x(:\n')

    proc = _run(tree, 'quick', 'unit', '--rerun', 'tests/utils/test_broken.py::test_x')

    assert proc.returncode == 1
    rerun = tree / 'test-results' / 'quick' / 'rerun' / '1'
    assert _xml_reports(rerun) == []
    assert _cases(rerun / 'junit.xml.no-verdict')['unit'][0] == 'failure'


def test_a_rerun_keeps_the_reports_of_a_step_that_reached_a_verdict_beside_one_that_did_not(
    tree: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    _fake_tavern(tree, monkeypatch, 77)

    proc = _run(tree, 'full', 'unit', 'tavern', '--rerun', 'tests/utils/test_sample.py::test_fails', _FIND_TEXT_ID)

    assert proc.returncode == 1
    rerun = tree / 'test-results' / 'full' / 'rerun' / '1'
    assert _xml_reports(rerun) == [rerun / 'unit.xml']
    assert _cases(rerun / 'unit.xml') == {'test_fails': ('failure', 'assert False')}
    assert (rerun / 'tavern-g.xml.no-verdict').is_file()
    assert _cases(rerun / 'junit.xml.no-verdict')['tavern'][0] == 'skipped'


_EXISTING_TAVERN_ID = 'bridge_api_patterns.get_post.gtg.tavern.yaml::Hivemind'


@pytest.fixture
def tavern_tree(tree: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """`tree` with the real tavern step, the files it reads before asking the provider, and one tavern test."""
    for name in ('hivemind_tavern.py', 'hivemind_smoke.py', 'hivemind_rewriter.py'):
        shutil.copy(AIDEV / name, tree / '.aidev' / name)
    (tree / '.aidev' / 'shared-hivemind').mkdir()
    shutil.copy(AIDEV / 'shared-hivemind' / 'shared_fixture.py', tree / '.aidev' / 'shared-hivemind')
    patchlevel = tree / 'hive' / 'db' / 'sql_scripts' / 'upgrade' / 'update_db_patchlevel.sql'
    patchlevel.parent.mkdir(parents=True)
    patchlevel.write_text(f"values (now(), '{'a' * 40}') -- merge request\n")
    (tree / '.aidev' / 'project.yaml').write_text(f'      env:\n        HAF_FIXTURE_COMMIT: "{"b" * 40}"\n')
    (tree / '.gitlab-ci.yml').write_text('  SMOKETESTS=(\n    "bridge_api_patterns:api_smoketest_bridge.xml"\n  )\n')
    test = tree / 'tests' / 'api_tests' / 'hivemind' / 'tavern' / 'bridge_api_patterns' / 'get_post' / 'gtg.tavern.yaml'
    test.parent.mkdir(parents=True)
    test.write_text('test_name: Hivemind\n')
    for variable in ('GIT_AUTHOR_NAME', 'GIT_COMMITTER_NAME'):
        monkeypatch.setenv(variable, 'test')
    for variable in ('GIT_AUTHOR_EMAIL', 'GIT_COMMITTER_EMAIL'):
        monkeypatch.setenv(variable, 'test@example.com')
    for args in (['init', '-q'], ['add', '-A'], ['commit', '-q', '-m', 'tree']):
        subprocess.run(['git', '-C', str(tree), *args], check=True)
    for name in [name for name in os.environ if name.startswith('AIDEV_EXTERNAL_HIVEMIND_')]:
        monkeypatch.delenv(name)
    return tree


@pytest.mark.parametrize('provider', [False, True])
def test_a_tavern_rerun_of_a_file_not_in_the_tree_is_a_verdict_of_absent(
    tavern_tree: Path, monkeypatch: pytest.MonkeyPatch, provider: bool
) -> None:
    if provider:
        # Unreachable: the selector is resolved before the provider is asked for anything.
        monkeypatch.setenv('AIDEV_EXTERNAL_HIVEMIND_HOST', 'hivemind.invalid')
        monkeypatch.setenv('AIDEV_EXTERNAL_HIVEMIND_PORT', '5432')

    proc = _run(tavern_tree, 'full', 'tavern', '--rerun', 'does_not.exist.tavern.yaml::Hivemind')

    assert proc.returncode == 1
    rerun = tavern_tree / 'test-results' / 'full' / 'rerun' / '1'
    assert _xml_reports(rerun) == [rerun / 'junit.xml', rerun / 'tavern-rerun-ids.xml']
    assert _cases(rerun / 'tavern-rerun-ids.xml') == {
        'rerun-ids': ('failure', 'selectors naming no test of a tavern group: does_not.exist.tavern.yaml::Hivemind')
    }
    assert _cases(rerun / 'junit.xml')['tavern'][0] == 'skipped'
    for report in _xml_reports(rerun):
        assert 'does_not.exist.tavern.yaml::Hivemind' not in _names(report)


def test_a_tavern_rerun_of_a_file_in_the_tree_without_a_provider_skips_and_leaves_no_report(
    tavern_tree: Path,
) -> None:
    proc = _run(tavern_tree, 'full', 'tavern', '--rerun', _EXISTING_TAVERN_ID)

    assert proc.returncode == 1
    rerun = tavern_tree / 'test-results' / 'full' / 'rerun' / '1'
    assert _xml_reports(rerun) == []
    outcome, message = _cases(rerun / 'junit.xml.no-verdict')['tavern']
    assert outcome == 'skipped'
    assert 'AIDEV_EXTERNAL_HIVEMIND_HOST/PORT unset' in message


_SMOKE_SQL_ID = 'api-smoke::sql/tests/sql/post_batches_staged_join.sql'

# An api-smoke step stand-in: the real call list; a run keeps its argv, writes a report passing the
# calls it is given and another one, then exits with $FAKE_SMOKE_RC.
_FAKE_SMOKE = '''import json, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'real'))
import hivemind_smoke
if sys.argv[1:] == ['--list']:
    print('\\n'.join(hivemind_smoke.call_names()))
    sys.exit(0)
with open(os.path.join(sys.argv[1], 'smoke-argv.json'), 'w') as handle:
    json.dump(sys.argv[2:], handle)
cases = ''.join(f'<testcase classname="api-smoke" name="{name}"/>' for name in sys.argv[2:] + ['other'])
with open(os.path.join(sys.argv[1], 'api-smoke.xml'), 'w') as report:
    report.write(f'<testsuite>{cases}</testsuite>')
sys.exit(int(os.environ.get('FAKE_SMOKE_RC', '0')))
'''


@pytest.fixture
def smoke_tree(tree: Path) -> Path:
    # `tree` with an api-smoke step stand-in that lists the real calls.
    (tree / '.aidev' / 'real').mkdir()
    shutil.copy(AIDEV / 'hivemind_smoke.py', tree / '.aidev' / 'real' / 'hivemind_smoke.py')
    (tree / '.aidev' / 'hivemind_smoke.py').write_text(_FAKE_SMOKE)
    return tree


def test_an_api_smoke_rerun_makes_only_the_named_call_and_reports_it_under_its_id(smoke_tree: Path) -> None:
    proc = _run(smoke_tree, 'baseline', 'api-smoke', '--rerun', _SMOKE_SQL_ID)

    assert proc.returncode == 0, proc.stderr
    rerun = smoke_tree / 'test-results' / 'baseline' / 'rerun' / '1'
    assert (rerun / 'smoke-argv.json').read_text() == '["sql/tests/sql/post_batches_staged_join.sql"]'
    assert _xml_reports(rerun) == [rerun / 'api-smoke.xml', rerun / 'junit.xml']
    assert _SMOKE_SQL_ID in _names(rerun / 'api-smoke.xml')
    assert _cases(rerun / 'junit.xml') == {'api-smoke': ('pass', '')}


def test_an_api_smoke_rerun_of_a_call_the_tree_does_not_make_is_a_verdict_of_absent(smoke_tree: Path) -> None:
    missing = 'api-smoke::sql/tests/sql/does_not_exist.sql'

    proc = _run(smoke_tree, 'baseline', 'install', 'api-smoke', '--rerun', missing)

    assert proc.returncode == 1
    rerun = smoke_tree / 'test-results' / 'baseline' / 'rerun' / '1'
    assert _xml_reports(rerun) == [rerun / 'junit.xml']
    assert _cases(rerun / 'junit.xml') == {
        'rerun-absent': ('failure', f're-run ids naming no test of this tree: {missing}')
    }
    assert missing not in _names(rerun / 'junit.xml')


def test_an_api_smoke_rerun_whose_install_fails_leaves_no_report(smoke_tree: Path) -> None:
    # The scratch tree has no install scripts to stage, so install fails before reaching any database.
    proc = _run(smoke_tree, 'baseline', 'install', 'reinstall', 'api-smoke', '--rerun', _SMOKE_SQL_ID)

    assert proc.returncode == 1
    rerun = smoke_tree / 'test-results' / 'baseline' / 'rerun' / '1'
    assert _xml_reports(rerun) == []
    assert not (rerun / 'smoke-argv.json').exists()
    assert _cases(rerun / 'junit.xml.no-verdict') == {'install': ('failure', 'exit 1')}


def test_an_api_smoke_rerun_whose_step_reached_no_verdict_keeps_no_report_naming_other_calls(
    smoke_tree: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv('FAKE_SMOKE_RC', '2')

    proc = _run(smoke_tree, 'baseline', 'api-smoke', '--rerun', _SMOKE_SQL_ID)

    assert proc.returncode == 1
    rerun = smoke_tree / 'test-results' / 'baseline' / 'rerun' / '1'
    assert _xml_reports(rerun) == []
    assert (rerun / 'api-smoke.xml.no-verdict').is_file()
    assert _cases(rerun / 'junit.xml.no-verdict')['api-smoke'] == ('failure', 'exit 2')


def _smoke(out: Path, *args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ['python3', str(AIDEV / 'hivemind_smoke.py'), str(out), *args],
        capture_output=True,
        text=True,
        timeout=60,
        env=env,
    )


def test_the_api_smoke_step_lists_the_calls_its_report_names() -> None:
    proc = subprocess.run(
        ['python3', str(AIDEV / 'hivemind_smoke.py'), '--list'], capture_output=True, text=True, timeout=60
    )

    assert proc.returncode == 0
    names = proc.stdout.splitlines()
    assert 'sql/tests/sql/post_batches_staged_join.sql' in names
    assert 'jsonrpc/hive.get_info' in names
    assert len(names) == len(set(names))


def test_the_api_smoke_step_reaches_no_verdict_on_a_call_it_does_not_make(tmp_path: Path) -> None:
    proc = _smoke(tmp_path, 'jsonrpc/hive.get_info', 'jsonrpc/no_such_call')

    assert proc.returncode == 2
    assert 'no such api-smoke calls: jsonrpc/no_such_call' in proc.stdout
    assert list(tmp_path.iterdir()) == []


def test_the_api_smoke_step_reaches_no_verdict_when_it_crashes(tmp_path: Path) -> None:
    env = {name: value for name, value in os.environ.items() if name != 'HIVEMIND_TEST_USER_URL'}

    proc = _smoke(tmp_path, 'jsonrpc/hive.get_info', env=env)

    assert proc.returncode == 2
    assert 'api-smoke step crashed' in proc.stdout
    assert not (tmp_path / 'api-smoke.xml').exists()


_FAKE_POSTGREST = '''#!/usr/bin/env python3
import http.server, os


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(b'{}')

    def log_message(self, *args):
        pass


http.server.HTTPServer(('127.0.0.1', int(os.environ['PGRST_SERVER_PORT'])), Handler).serve_forever()
'''


@pytest.mark.parametrize(
    ('psql', 'expected'),
    [
        (
            "echo 'psql:post_batches_staged_join.sql:560: ERROR:  results differ' >&2; exit 3",
            'psql exited 3: psql:post_batches_staged_join.sql:560: ERROR:  results differ',
        ),
        ('kill -9 $$', 'psql was killed by SIGKILL'),
    ],
)
def test_a_failing_sql_script_reports_how_psql_ended_in_its_junit_case(
    tmp_path: Path, psql: str, expected: str
) -> None:
    bin_dir = tmp_path / 'bin'
    bin_dir.mkdir()
    for name, body in (('postgrest', _FAKE_POSTGREST), ('psql', f'#!/bin/sh\n{psql}\n')):
        (bin_dir / name).write_text(body)
        (bin_dir / name).chmod(0o755)
    out = tmp_path / 'out'
    env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}", HIVEMIND_TEST_USER_URL='postgresql://x@127.0.0.1/x')

    proc = _smoke(out, 'sql/tests/sql/post_batches_staged_join.sql', env=env)

    assert proc.returncode == 1, proc.stdout
    case = next(ET.parse(out / 'api-smoke.xml').getroot().iter('testcase'))
    failure = case.find('failure')
    assert case.get('name') == 'sql/tests/sql/post_batches_staged_join.sql'
    assert failure is not None
    assert failure.get('message', '').startswith(expected)
    assert expected.split(': ')[-1] in (failure.text or '')
