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
HAF = '2ae98b8225165ce9eebb4f1858b81e50c5a705b3'
RECIPE_A = '1' * 64
RECIPE_B = '2' * 64
RT_COMMIT = '1d66314fc8ecd879618a3f220a80cd4671badd80'
HAFAH_COMMIT = '4eee96d7109cd8d72e7f661c122a5610ac5c2078'


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


def _template(rev: str, recipe: str) -> Any:
    return fixture.Template(rev, recipe, f'hivemind_{rev}_{recipe[:12]}')


def test_select_template_prefers_the_exact_recipe_over_a_newer_one() -> None:
    templates = [_template(REV_B, RECIPE_B), _template(REV_B, RECIPE_A), _template(REV_A, RECIPE_A)]

    assert fixture.select_template(templates, REV_B, RECIPE_A) == _template(REV_B, RECIPE_A)
    assert fixture.select_template(templates, REV_A, RECIPE_A) == _template(REV_A, RECIPE_A)


def test_select_template_falls_back_to_the_newest_of_the_revision_only() -> None:
    templates = [_template(REV_A, RECIPE_B), _template(REV_B, RECIPE_B), _template(REV_B, 'unrecorded')]

    assert fixture.select_template(templates, REV_B, RECIPE_A) == _template(REV_B, RECIPE_B)
    assert fixture.select_template(templates, 'c' * 40, RECIPE_B) is None
    assert fixture.select_template([], REV_A, RECIPE_A) is None


def test_fallback_message_names_both_recipes_and_the_request() -> None:
    message = fixture.fallback_message(_template(REV_B, RECIPE_B), RECIPE_A, requested=True)

    assert message.startswith('advisory: ')
    assert RECIPE_A[:12] in message and RECIPE_B[:12] in message and REV_B in message
    assert f'hivemind_{REV_B}_{RECIPE_B[:12]}' in message
    assert message.endswith('seeding requested')
    assert 'seeding not requested' in fixture.fallback_message(_template(REV_B, RECIPE_B), RECIPE_A, requested=False)


def test_retire_keeps_the_newest_per_revision_and_any_template_in_use() -> None:
    a = [_template(REV_A, str(i) * 64) for i in range(5)]
    b = [_template(REV_B, str(i) * 64) for i in range(2)]
    listed = [(a[0], 0), (b[0], 0), (a[1], 2), (a[2], 0), (b[1], 0), (a[3], 1), (a[4], 0)]

    assert fixture.retire(listed, keep=3) == [a[4]]
    assert fixture.retire(listed, keep=1) == [a[2], b[1], a[4]]
    assert fixture.retire(listed, keep=5) == []
    with pytest.raises(ValueError):
        fixture.retire(listed, keep=0)


def test_retire_cli_reads_health_rows_and_prints_template_names() -> None:
    rows = ''.join(f'{REV_A} {str(i) * 64} hivemind_{REV_A}_{i} {live}\n' for i, live in enumerate([0, 0, 0, 1, 0]))

    proc = subprocess.run(
        [sys.executable, str(FIXTURE_PY), 'retire', '3'], input=rows, capture_output=True, text=True, check=True
    )

    assert proc.stdout.split() == [f'hivemind_{REV_A}_4']


def test_haf_fixture_commit_is_the_shared_hivemind_pin() -> None:
    project = (AIDEV / 'project.yaml').read_text()

    assert fixture.haf_fixture_commit(project) == re.search(r'HAF_FIXTURE_COMMIT: "([0-9a-f]{40})"', project).group(1)
    assert fixture.haf_fixture_commit('env:\n  HAF_FIXTURE_DIGEST: "sha256:00"\n') is None


def _git(root: Path, *args: str) -> str:
    return subprocess.run(['git', '-C', str(root), *args], check=True, capture_output=True, text=True).stdout.strip()


def _git_identity(monkeypatch: pytest.MonkeyPatch) -> None:
    for role in ('AUTHOR', 'COMMITTER'):
        monkeypatch.setenv(f'GIT_{role}_NAME', 'test')
        monkeypatch.setenv(f'GIT_{role}_EMAIL', 'test@example.com')


# One tracked file under each of the recipe's inputs.
_RECIPE_FILES = [
    'scripts/ci/add-mocks-to-db.sh',
    'scripts/ci/wrapper_for_app_next_block.sql',
    'scripts/install_app.sh',
    'scripts/install_app.sql',
    'scripts/setup_postgres.sh',
    'mock_data/block_data/follow_op/mock_block_data_follow.json',
    'hive/indexer/blocks.py',
    'hive/indexer/mocking/populate_haf_with_mocked_data.py',
    'hive/utils/normalize.py',
    'hive/db/schema.py',
    'hive/db/sql_scripts/massive_sync.sql',
    'hive/db/sql_scripts/schema/tables.sql',
    PATCHLEVEL,
    '.aidev/shared-hivemind/seed.sh',
]
_UNRELATED_FILES = [
    'README.md',
    'hive/server/serve.py',
    'hive/db/sql_scripts/postgrest/bridge_api/get_post.sql',
    'hive/db/sql_scripts/endpoints/endpoint.sql',
    'scripts/ci/start-api-smoketest.sh',
    'tests/api_tests/hivemind/tavern/bridge_api_patterns/get_post/x.pat.json',
    '.aidev/shared-hivemind/seeder.sh',
]


@pytest.fixture
def checkout(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    _git_identity(monkeypatch)
    root = tmp_path / 'checkout'
    for name in _RECIPE_FILES + _UNRELATED_FILES:
        (root / name).parent.mkdir(parents=True, exist_ok=True)
        (root / name).write_text(f'{name}\n')
    _git(root, 'init', '-q')
    _git(root, 'add', '-A')
    for path, sha in (('reputation_tracker', RT_COMMIT), ('hafah', HAFAH_COMMIT)):
        _git(root, 'update-index', '--add', '--cacheinfo', f'160000,{sha},{path}')
    _git(root, 'commit', '-q', '-m', 'checkout')
    return root


def _commit(root: Path, *paths: str) -> None:
    # Not `add -A`: the submodules are gitlinks without a checkout, which it would stage as deleted.
    _git(root, 'add', '--', *paths)
    _git(root, 'commit', '-q', '-m', 'change')


def test_recipe_of_a_clean_checkout_is_its_head_commits(checkout: Path) -> None:
    tree = fixture.recipe_of_tree(str(checkout), HAF)

    assert fixture.RECIPE_RE.match(tree)
    assert tree == fixture.recipe_of_commit(str(checkout / '.git'), _git(checkout, 'rev-parse', 'HEAD'), HAF)


@pytest.mark.parametrize('name', _RECIPE_FILES)
def test_recipe_changes_with_each_input_file(checkout: Path, name: str) -> None:
    before = fixture.recipe_of_tree(str(checkout), HAF)
    (checkout / name).write_text('changed\n')
    dirty = fixture.recipe_of_tree(str(checkout), HAF)
    _commit(checkout, name)

    assert dirty != before
    assert fixture.recipe_of_commit(str(checkout / '.git'), 'HEAD', HAF) == dirty


@pytest.mark.parametrize('path', ['reputation_tracker', 'hafah'])
def test_recipe_changes_with_each_submodule_commit(checkout: Path, path: str) -> None:
    before = fixture.recipe_of_tree(str(checkout), HAF)
    _git(checkout, 'update-index', '--cacheinfo', f'160000,{"f" * 40},{path}')
    _git(checkout, 'commit', '-q', '-m', 'bump')

    assert fixture.recipe_of_tree(str(checkout), HAF) != before
    assert fixture.recipe_of_commit(str(checkout / '.git'), 'HEAD', HAF) != before


def test_recipe_changes_with_the_haf_commit(checkout: Path) -> None:
    assert fixture.recipe_of_tree(str(checkout), HAF) != fixture.recipe_of_tree(str(checkout), 'e' * 40)
    with pytest.raises(ValueError):
        fixture.recipe_of_tree(str(checkout), 'develop')


def test_recipe_ignores_unrelated_and_untracked_files(checkout: Path) -> None:
    before = fixture.recipe_of_tree(str(checkout), HAF)
    for name in _UNRELATED_FILES:
        (checkout / name).write_text('changed\n')
    (checkout / 'hive/indexer/__pycache__').mkdir()
    (checkout / 'hive/indexer/__pycache__/blocks.cpython-314.pyc').write_bytes(b'\0')
    (checkout / 'mock_data/new.json').write_text('{}\n')

    assert fixture.recipe_of_tree(str(checkout), HAF) == before
    _commit(checkout, *_UNRELATED_FILES)
    assert fixture.recipe_of_commit(str(checkout / '.git'), 'HEAD', HAF) == before


def test_recipe_cli_reads_a_shallow_bare_fetch_as_the_seeder_does(checkout: Path, tmp_path: Path) -> None:
    head = _git(checkout, 'rev-parse', 'HEAD')
    bare = tmp_path / 'refs.git'
    subprocess.run(['git', 'init', '-q', '--bare', str(bare)], check=True)
    subprocess.run(
        ['git', '--git-dir', str(bare), 'fetch', '-q', '--depth', '1', f'file://{checkout}', head], check=True
    )

    cli = [sys.executable, str(FIXTURE_PY), 'recipe']
    from_commit = subprocess.run([*cli, 'commit', str(bare), head, HAF], capture_output=True, text=True, check=True)
    from_tree = subprocess.run([*cli, 'tree', str(checkout), HAF], capture_output=True, text=True, check=True)
    refused = subprocess.run([*cli, 'commit', str(bare), 'f' * 40, HAF], capture_output=True, text=True)

    assert from_commit.stdout.strip() == from_tree.stdout.strip() == fixture.recipe_of_tree(str(checkout), HAF)
    assert refused.returncode == 1
    assert refused.stdout == ''


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
    assert "'^[0-9a-f]{64}$'" in admin_sql
    assert fixture.RECIPE_RE.pattern == '^[0-9a-f]{64}$'
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
    for entry in os.environ.get('FAKE_TEMPLATES', '').split():
        rev, recipe = entry.split(':')
        print(f'{rev} {recipe} hivemind_{rev}_{recipe[:12]}')
elif 'to_regprocedure' in sql:
    print('f' if os.environ.get('FAKE_OLD_API') else 't')
elif 'request_seed' in sql:
    print('pending')
elif 'clone_run_database' in sql:
    print('run_' + variables['run'])
'''


@pytest.fixture
def tree(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    _git_identity(monkeypatch)
    root = tmp_path / 'tree'
    (root / '.aidev' / 'shared-hivemind').mkdir(parents=True)
    for name in ('hivemind_tavern.py', 'hivemind_smoke.py'):
        shutil.copy(AIDEV / name, root / '.aidev' / name)
    shutil.copy(FIXTURE_PY, root / '.aidev' / 'shared-hivemind' / 'shared_fixture.py')
    (root / PATCHLEVEL).parent.mkdir(parents=True)
    (root / PATCHLEVEL).write_text(_patchlevel(REV_A, REV_B))
    (root / '.aidev' / 'project.yaml').write_text(f'      env:\n        HAF_FIXTURE_COMMIT: "{HAF}"\n')
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
    recipe = fixture.recipe_of_tree(str(tree), HAF)
    monkeypatch.setenv('FAKE_TEMPLATES', f'{REV_A}:{recipe}')

    rc, lines, calls = _run_step(tree, tmp_path / 'out')

    assert rc == SKIP
    assert lines[-1] == f'no hivemind fixture for schema revision {REV_B}; seeding requested'
    seeds = [call['vars'] for call in calls if "request_seed(:" in call['sql']]
    assert seeds == [{'rev': REV_B, 'recipe': recipe, 'commit': _git(tree, 'rev-parse', 'HEAD')}]
    assert not any('clone_run_database' in call['sql'] for call in calls)


def test_a_recipe_miss_clones_the_newest_of_the_revision_with_an_advisory_and_requests_the_exact_seed(
    tree: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    recipe = fixture.recipe_of_tree(str(tree), HAF)
    monkeypatch.setenv('FAKE_TEMPLATES', f'{REV_B}:{RECIPE_B} {REV_B}:{RECIPE_A} {REV_A}:{recipe}')

    rc, lines, calls = _run_step(tree, tmp_path / 'out')

    seeds = [call['vars'] for call in calls if "request_seed(:" in call['sql']]
    clones = [call['vars'] for call in calls if 'clone_run_database' in call['sql']]
    assert seeds == [{'rev': REV_B, 'recipe': recipe, 'commit': _git(tree, 'rev-parse', 'HEAD')}]
    assert fixture.fallback_message(_template(REV_B, RECIPE_B), recipe, requested=True) in lines
    assert [(clone['rev'], clone['recipe']) for clone in clones] == [(REV_B, RECIPE_B)]
    assert rc == 1
    assert 'reloading the tree' in lines[-1]


def test_a_provider_with_the_old_clone_api_skips_by_name(
    tree: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv('FAKE_OLD_API', '1')
    monkeypatch.setenv('FAKE_TEMPLATES', f'{REV_B}:{RECIPE_A}')

    rc, lines, calls = _run_step(tree, tmp_path / 'out')

    assert rc == SKIP
    assert 'predates sync recipes' in lines[-1]
    assert len(calls) == 1 and 'to_regprocedure' in calls[0]['sql']


def test_without_a_provider_the_step_skips_by_name(tree: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv('AIDEV_EXTERNAL_HIVEMIND_HOST')

    rc, lines, calls = _run_step(tree, tmp_path / 'out')

    assert rc == SKIP
    assert 'AIDEV_EXTERNAL_HIVEMIND_HOST' in lines[-1]
    assert calls == []


def test_an_exact_hit_clones_that_template_without_a_seed_request_and_drops_the_clone_when_the_run_fails(
    tree: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    recipe = fixture.recipe_of_tree(str(tree), HAF)
    monkeypatch.setenv('FAKE_TEMPLATES', f'{REV_B}:{RECIPE_A} {REV_A}:{recipe} {REV_B}:{recipe}')

    rc, lines, calls = _run_step(tree, tmp_path / 'out')

    clones = [call['vars'] for call in calls if 'clone_run_database' in call['sql']]
    drops = [call['vars'] for call in calls if 'drop_run_database' in call['sql']]
    assert rc == 1
    assert 'reloading the tree' in lines[-1]
    assert not any('advisory' in line for line in lines)
    assert not any("request_seed(:" in call['sql'] for call in calls)
    assert len(clones) == 1
    assert (clones[0]['rev'], clones[0]['recipe']) == (REV_B, recipe)
    assert re.fullmatch(r'tavern-\d{8}t\d{6}-[0-9a-f]{8}', clones[0]['run'])
    assert drops == [{'run': clones[0]['run']}]
    assert (
        'reload refused: --postgres-url=postgresql://hivemind@hivemind:5432/run_tavern-'
        in (tmp_path / 'out' / 'tavern-reload.log').read_text()
    )
