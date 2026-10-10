import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path
from types import ModuleType
from typing import Any

import pytest

ROOT = Path(__file__).resolve().parents[2]
AIDEV = ROOT / '.aidev'
FIXTURE_PY = AIDEV / 'shared-hivemind' / 'shared_fixture.py'
PATCHLEVEL = 'hive/db/sql_scripts/upgrade/update_db_patchlevel.sql'
SKIP = 77
REV_A = 'a' * 40
REV_B = '0123456789abcdef0123456789abcdef01234567'


def _load(name: str, path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f'cannot load {path}')
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


fixture = _load('shared_fixture', FIXTURE_PY)


def _patchlevel(*revisions: str) -> str:
    values = ',\n'.join(f" (now(), '{rev}') -- merge request" for rev in revisions)
    return f'insert into hivemind_app.hive_db_patch_level (patch_date, patched_to_revision)\nselect * from (values\n{values}\n) ds;\n'


def test_revision_of_the_tree_is_what_ci_greps() -> None:
    ci = subprocess.run(
        ['bash', '-c', f"grep -oP \"'\\K[a-f0-9]{{40}}(?=')\" {ROOT / PATCHLEVEL} | tail -1"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()

    assert re.fullmatch(r'[0-9a-f]{40}', ci)
    assert fixture.revision((ROOT / PATCHLEVEL).read_text()) == ci


def test_revision_is_the_last_quoted_hash() -> None:
    assert fixture.revision(_patchlevel(REV_A, REV_B)) == REV_B


@pytest.mark.parametrize(
    'text',
    ['', "values (now(), 'abc123')", f'values (now(), {REV_A})', f"values (now(), '{REV_A.upper()}')", f"'{REV_A}0'"],
)
def test_revision_is_none_without_a_quoted_40_hex_hash(text: str) -> None:
    assert fixture.revision(text) is None


def test_revision_cli_reads_stdin_and_refuses_a_file_without_one(tmp_path: Path) -> None:
    ok = subprocess.run(
        [sys.executable, str(FIXTURE_PY), 'revision', '-'], input=_patchlevel(REV_B), capture_output=True, text=True
    )
    empty = tmp_path / 'empty.sql'
    empty.write_text('select 1;\n')
    missing = subprocess.run([sys.executable, str(FIXTURE_PY), 'revision', str(empty)], capture_output=True, text=True)

    assert (ok.returncode, ok.stdout.strip()) == (0, REV_B)
    assert missing.returncode == 1
    assert missing.stdout == ''


def test_select_template_picks_the_matching_revision_only() -> None:
    templates = [fixture.Template(REV_A, f'hivemind_{REV_A}'), fixture.Template(REV_B, f'hivemind_{REV_B}')]

    assert fixture.select_template(templates, REV_B) == fixture.Template(REV_B, f'hivemind_{REV_B}')
    assert fixture.select_template(templates, 'c' * 40) is None
    assert fixture.select_template([], REV_A) is None


def test_miss_message_names_the_revision_and_the_request() -> None:
    assert fixture.miss_message(REV_A, requested=True) == (
        f'no hivemind fixture for schema revision {REV_A}; seeding requested'
    )
    assert 'seeding not requested' in fixture.miss_message(REV_A, requested=False)


def test_run_ids_are_accepted_by_the_clone_api_and_unique() -> None:
    now = datetime(2026, 10, 10, 6, 17, 5, tzinfo=UTC)
    ids = {fixture.new_run_id('tavern', now) for _ in range(200)}
    admin_sql = (AIDEV / 'shared-hivemind' / 'admin.sql').read_text()

    assert "'^[a-z0-9][a-z0-9_-]{0,47}$'" in admin_sql
    assert len(ids) == 200
    for run_id in ids:
        assert re.fullmatch(r'tavern-20261010t061705-[0-9a-f]{8}', run_id)
        assert re.fullmatch(r'[a-z0-9][a-z0-9_-]{0,47}', run_id)


@pytest.mark.parametrize('prefix', ['Tavern', '-x', 'x' * 30])
def test_run_id_refuses_a_prefix_the_clone_api_would(prefix: str) -> None:
    with pytest.raises(ValueError, match='refuses'):
        fixture.new_run_id(prefix)


def test_smoketest_groups_are_the_ci_list() -> None:
    sys.path.insert(0, str(AIDEV))
    try:
        tavern = _load('hivemind_tavern', AIDEV / 'hivemind_tavern.py')
    finally:
        sys.path.remove(str(AIDEV))
    groups = tavern.smoketest_groups((ROOT / '.gitlab-ci.yml').read_text())

    assert groups[:2] == ['condenser_api_patterns', 'condenser_api_negative']
    assert {'bridge_api_patterns', 'postgrest_negative', 'mock_tests'} <= set(groups)
    assert all((ROOT / 'tests/api_tests/hivemind/tavern' / group).is_dir() for group in groups)
    with pytest.raises(ValueError):
        tavern.smoketest_groups('script: []\n')


# A psql stand-in: records each call's variables and SQL, answers the clone API.
_FAKE_PSQL = r'''#!/usr/bin/env python3
import json, os, sys
args, variables = sys.argv[1:], {}
for i, arg in enumerate(args):
    if args[i - 1] == '-v' and '=' in arg and not arg.startswith('ON_ERROR_STOP'):
        key, value = arg.split('=', 1)
        variables[key] = value
sql = sys.stdin.read()
with open(os.environ['FAKE_PSQL_LOG'], 'a') as log:
    log.write(json.dumps({'sql': sql, 'vars': variables}) + '\n')
if 'health()' in sql:
    for rev in os.environ.get('FAKE_TEMPLATES', '').split():
        print(f'{rev} hivemind_{rev}')
elif 'request_seed' in sql:
    print('pending')
elif 'clone_run_database' in sql:
    print('run_' + variables['run'])
'''


@pytest.fixture
def tree(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    for role in ('AUTHOR', 'COMMITTER'):
        monkeypatch.setenv(f'GIT_{role}_NAME', 'test')
        monkeypatch.setenv(f'GIT_{role}_EMAIL', 'test@example.com')
    root = tmp_path / 'tree'
    (root / '.aidev' / 'shared-hivemind').mkdir(parents=True)
    for name in ('hivemind_tavern.py', 'hivemind_smoke.py'):
        shutil.copy(AIDEV / name, root / '.aidev' / name)
    shutil.copy(FIXTURE_PY, root / '.aidev' / 'shared-hivemind' / 'shared_fixture.py')
    (root / PATCHLEVEL).parent.mkdir(parents=True)
    (root / PATCHLEVEL).write_text(_patchlevel(REV_A, REV_B))
    (root / '.gitlab-ci.yml').write_text('  SMOKETESTS=(\n    "bridge_api_patterns:api_smoketest_bridge.xml"\n  )\n')
    reload = root / 'scripts' / 'ci' / 'reload-postgrest-functions.sh'
    reload.parent.mkdir(parents=True)
    reload.write_text('#!/bin/sh\necho "reload refused: $*"\nexit 3\n')
    reload.chmod(0o755)
    subprocess.run(['git', '-C', str(root), 'init', '-q'], check=True)
    subprocess.run(['git', '-C', str(root), 'add', '-A'], check=True)
    subprocess.run(['git', '-C', str(root), 'commit', '-q', '-m', 'tree'], check=True)
    bin_dir = tmp_path / 'bin'
    bin_dir.mkdir()
    (bin_dir / 'psql').write_text(_FAKE_PSQL)
    (bin_dir / 'psql').chmod(0o755)
    monkeypatch.setenv('PATH', f'{bin_dir}{os.pathsep}{os.environ["PATH"]}')
    monkeypatch.setenv('FAKE_PSQL_LOG', str(tmp_path / 'psql.jsonl'))
    monkeypatch.setenv('AIDEV_EXTERNAL_HIVEMIND_HOST', 'hivemind')
    monkeypatch.setenv('AIDEV_EXTERNAL_HIVEMIND_PORT', '5432')
    return root


def _run_step(tree: Path, out: Path) -> tuple[int, list[str], list[dict[str, Any]]]:
    proc = subprocess.run(
        [sys.executable, str(tree / '.aidev' / 'hivemind_tavern.py'), str(out)], capture_output=True, text=True
    )
    log = Path(os.environ['FAKE_PSQL_LOG'])
    calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
    return proc.returncode, proc.stdout.strip().splitlines(), calls


def test_revision_miss_requests_a_seed_and_skips(tree: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv('FAKE_TEMPLATES', REV_A)
    head = subprocess.run(['git', '-C', str(tree), 'rev-parse', 'HEAD'], check=True, capture_output=True, text=True)

    rc, lines, calls = _run_step(tree, tmp_path / 'out')

    assert rc == SKIP
    assert lines[-1] == f'no hivemind fixture for schema revision {REV_B}; seeding requested'
    seeds = [call['vars'] for call in calls if 'request_seed' in call['sql']]
    assert seeds == [{'rev': REV_B, 'commit': head.stdout.strip()}]
    assert not any('clone_run_database' in call['sql'] for call in calls)


def test_without_a_provider_the_step_skips_by_name(tree: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv('AIDEV_EXTERNAL_HIVEMIND_HOST')

    rc, lines, calls = _run_step(tree, tmp_path / 'out')

    assert rc == SKIP
    assert 'AIDEV_EXTERNAL_HIVEMIND_HOST' in lines[-1]
    assert calls == []


def test_a_hit_clones_that_revision_and_drops_the_clone_when_the_run_fails(
    tree: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv('FAKE_TEMPLATES', f'{REV_A} {REV_B}')

    rc, lines, calls = _run_step(tree, tmp_path / 'out')

    clones = [call['vars'] for call in calls if 'clone_run_database' in call['sql']]
    drops = [call['vars'] for call in calls if 'drop_run_database' in call['sql']]
    assert rc == 1
    assert 'reloading the tree' in lines[-1]
    assert len(clones) == 1
    assert clones[0]['rev'] == REV_B
    assert re.fullmatch(r'tavern-\d{8}t\d{6}-[0-9a-f]{8}', clones[0]['run'])
    assert drops == [{'run': clones[0]['run']}]
    assert (
        'reload refused: --postgres-url=postgresql://hivemind@hivemind:5432/run_tavern-'
        in (tmp_path / 'out' / 'tavern-reload.log').read_text()
    )
