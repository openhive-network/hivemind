import importlib.util
import json
import subprocess
import sys
import zipfile
from pathlib import Path
from typing import Any

import pytest

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts' / 'ci' / 'generate_patterns.py'
_spec = importlib.util.spec_from_file_location('generate_patterns', SCRIPT)
assert _spec is not None and _spec.loader is not None
gp = importlib.util.module_from_spec(_spec)
sys.modules['generate_patterns'] = gp
_spec.loader.exec_module(gp)

TAVERN = Path('tests/api_tests/hivemind/tavern')
POST = TAVERN / 'bridge_api_patterns/get_post_v2/observer_voted'
VOTES = TAVERN / 'bridge_api_patterns/list_votes/first_page'
EMPTY = TAVERN / 'bridge_api_patterns/get_discussion/observer_muted'


def _git(repo: Path, *args: str) -> str:
    return subprocess.run(['git', '-C', str(repo), *args], check=True, capture_output=True, text=True).stdout.strip()


def _test(root: Path, stem: Path, pattern: str | None = '{}') -> None:
    yaml = root / f'{stem}.tavern.yaml'
    yaml.parent.mkdir(parents=True, exist_ok=True)
    yaml.write_text('---\n  test_name: Hivemind\n')
    if pattern is not None:
        (root / f'{stem}.pat.json').write_text(pattern)


def _output(artifacts: Path, stem: Path, text: str) -> None:
    out = artifacts / f'{stem}.out.json'
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text)


@pytest.fixture
def repo(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    for role in ('AUTHOR', 'COMMITTER'):
        monkeypatch.setenv(f'GIT_{role}_NAME', 'test')
        monkeypatch.setenv(f'GIT_{role}_EMAIL', 'test@example.com')
    root = tmp_path / 'repo'
    root.mkdir()
    _git(root, 'init', '-q')
    monkeypatch.chdir(root)
    return root


@pytest.mark.parametrize(
    ('content', 'expected'),
    [('{}', True), ('{ }\n', True), (None, True), ('[]', False), ('{"a": 1}', False), ('{', False), ('null', False)],
)
def test_is_placeholder(tmp_path: Path, content: str | None, expected: bool) -> None:
    pattern = tmp_path / 'x.pat.json'
    if content is not None:
        pattern.write_text(content)

    assert gp.is_placeholder(pattern) is expected


def test_find_placeholders_lists_tests_whose_pattern_is_an_empty_object(tmp_path: Path) -> None:
    _test(tmp_path, POST, '{}\n')
    _test(tmp_path, VOTES, '[]')
    _test(tmp_path, EMPTY, None)
    (tmp_path / TAVERN / 'orphan.pat.json').write_text('{}')

    assert gp.find_placeholders(tmp_path) == [POST]


def test_apply_writes_outputs_and_reports_the_rest(tmp_path: Path) -> None:
    root, artifacts = tmp_path / 'repo', tmp_path / 'artifacts'
    _test(root, POST)
    _test(root, VOTES, None)
    _test(root, EMPTY)
    kept = TAVERN / 'bridge_api_patterns/get_post/kept'
    _test(root, kept, '{"author": "ned"}')
    post: dict[str, Any] = {'author': 'steemit', 'active_votes': [], 'observer_vote': None, 'stats': {'gray': False}}
    _output(artifacts, POST, json.dumps(post, indent=2) + '\n')
    _output(artifacts, VOTES, json.dumps([{'voter': 'ned', 'rshares': 1}, {'voter': 'dan', 'rshares': None}]))
    _output(artifacts, kept, '{"author": "steemit"}')

    report = gp.apply_artifacts(root, artifacts, [POST, VOTES, EMPTY, kept])

    written = json.loads((root / f'{POST}.pat.json').read_text())
    assert written == post
    assert (root / f'{POST}.pat.json').read_text() == json.dumps(post, sort_keys=True, indent=2) + '\n'
    assert json.loads((root / f'{VOTES}.pat.json').read_text())[1]['voter'] == 'dan'
    assert list(report.written) == [POST, VOTES]
    assert report.written[POST] == (
        '{4 keys: active_votes, author, observer_vote, stats} lists: active_votes[0]; nulls: observer_vote'
    )
    assert report.written[VOTES] == 'list[2] of {rshares, voter}; nulls: [].rshares'
    assert report.missing == [EMPTY]
    assert (root / f'{EMPTY}.pat.json').read_text() == '{}'
    assert report.kept == [kept]
    assert (root / f'{kept}.pat.json').read_text() == '{"author": "ned"}'
    assert not report.complete


def test_apply_with_force_overwrites_a_real_pattern(tmp_path: Path) -> None:
    root, artifacts = tmp_path / 'repo', tmp_path / 'artifacts'
    _test(root, POST, '{"author": "ned"}')
    _output(artifacts, POST, '{"author": "steemit"}')

    report = gp.apply_artifacts(root, artifacts, [POST], force=True)

    assert json.loads((root / f'{POST}.pat.json').read_text()) == {'author': 'steemit'}
    assert report.complete


@pytest.mark.parametrize(
    ('output', 'reason'),
    [
        ('{"jsonrpc": "2.0", "error": {"code": -32602}, "id": 1}', 'whole JSON-RPC response'),
        ('{"a": 1}\n{"a": 2}\n', 'not one JSON document'),
    ],
)
def test_apply_does_not_write_an_unusable_output(tmp_path: Path, output: str, reason: str) -> None:
    root, artifacts = tmp_path / 'repo', tmp_path / 'artifacts'
    _test(root, POST)
    _output(artifacts, POST, output)

    report = gp.apply_artifacts(root, artifacts, [POST])

    assert report.unusable[POST].startswith(reason)
    assert (root / f'{POST}.pat.json').read_text() == '{}'


def test_main_fills_patterns_from_an_artifact_zip(
    repo: Path, tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    _test(repo, POST)
    _test(repo, EMPTY)
    archive = tmp_path / 'artifacts.zip'
    with zipfile.ZipFile(archive, 'w') as zf:
        zf.writestr(f'{POST}.out.json', '{"author": "steemit"}')
        zf.writestr('hivemind-server.log', 'log')

    status = gp.main(['--artifacts', str(archive), f'{POST}.tavern.yaml', f'{EMPTY}.pat.json'])

    assert status == 1
    assert json.loads((repo / f'{POST}.pat.json').read_text()) == {'author': 'steemit'}
    out = capsys.readouterr().out
    assert f'written  {POST}.pat.json' in out
    assert f'MISSING  {EMPTY}' in out


def test_dry_run_prints_the_plan_without_pushing(repo: Path, capsys: pytest.CaptureFixture[str]) -> None:
    _test(repo, POST)
    _test(repo, VOTES, '[]')
    _git(repo, 'add', '.')
    _git(repo, 'commit', '-q', '-m', 'tests')
    head = _git(repo, 'rev-parse', '--short=8', 'HEAD')

    status = gp.main(['--dry-run', '--remote', 'nowhere', f'{POST}.tavern.yaml', f'{VOTES}.tavern.yaml'])

    assert status == 0
    out = capsys.readouterr().out
    assert f'branch:    patterns/{head}' in out
    assert 'variables: POSTGREST_ONLY_CHANGE=true AUTO_SKIP_SYNC=false' in out
    assert f'  {POST}\n' in out
    assert f'  {VOTES}  (has a pattern; kept without --force)' in out
    assert _git(repo, 'branch', '--list', 'patterns/*') == ''


def test_uncommitted_tests_are_refused(repo: Path, capsys: pytest.CaptureFixture[str]) -> None:
    _git(repo, 'commit', '-q', '--allow-empty', '-m', 'base')
    _test(repo, POST)

    status = gp.main(['--dry-run', f'{POST}.tavern.yaml'])

    assert status == 2
    assert 'commit these first' in capsys.readouterr().err


def test_a_path_that_is_not_a_tavern_test_is_refused(repo: Path, capsys: pytest.CaptureFixture[str]) -> None:
    _test(repo, POST)

    status = gp.main(['--dry-run', f'{POST}.out.json'])

    assert status == 2
    assert 'expected a .tavern.yaml or .pat.json path' in capsys.readouterr().err
