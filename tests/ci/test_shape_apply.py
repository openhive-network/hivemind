import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path
from types import ModuleType
from typing import Any

import pytest

import hive.indexer.hive_db.haf_functions as haf_functions
from hive.conf import SWAGGER_URL
from hive.db import schema

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / '.aidev' / 'shape_apply.py'
PATCHLEVEL = 'upgrade/update_db_patchlevel.sql'


def _load(name: str, path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f'cannot load {path}')
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


shape_apply = _load('shape_apply', SCRIPT)


class _Db:
    def query_no_return(self, sql: str) -> None:
        pass

    def query_one(self, sql: str) -> bool:
        return False


def _upgrade_scripts(monkeypatch: pytest.MonkeyPatch) -> tuple[list[Path], list[Path]]:
    """The scripts `hive upgrade_schema` runs as the admin and as the owner, in order."""
    ran: list[Path] = []
    monkeypatch.setattr(schema, 'execute_sql_script', lambda _executor, path: ran.append(Path(path)))
    monkeypatch.setattr(haf_functions, 'register_application', lambda _db: None)
    schema.perform_db_upgrade(db=_Db(), admin_db=_Db())
    admin = list(ran)
    schema.setup_runtime_code(db=_Db())
    return admin, ran[len(admin) :]


def test_the_scripts_are_those_hive_upgrade_schema_runs_in_its_order(monkeypatch: pytest.MonkeyPatch) -> None:
    admin, owner = _upgrade_scripts(monkeypatch)

    steps = shape_apply.plan()

    assert steps[0] == (shape_apply.ADMIN, ROOT / 'scripts' / 'install_app.sql')
    assert [path.resolve() for role, path in steps[1:] if role == shape_apply.ADMIN] == [p.resolve() for p in admin]
    expected_owner = [p.resolve() for p in owner if not p.as_posix().endswith(PATCHLEVEL)]
    assert [path.resolve() for role, path in steps if role == shape_apply.OWNER] == expected_owner
    assert len(expected_owner) == len(owner) - 1
    assert any(p.as_posix().endswith('postgrest/home.sql') for p in expected_owner)


# Records each session's standard input; exits 3 when it holds the text in FAKE_PSQL_FAIL.
_FAKE_PSQL = '''#!/usr/bin/env python3
import json, os, sys
sql = sys.stdin.read()
with open(os.environ['FAKE_PSQL_LOG'], 'a') as log:
    log.write(json.dumps({'argv': sys.argv[1:], 'sql': sql}) + '\\n')
fail = os.environ.get('FAKE_PSQL_FAIL')
if fail and fail in sql:
    print('psql:<stdin>:1: ERROR:  boom', file=sys.stderr)
    sys.exit(3)
'''


@pytest.fixture
def fake_psql(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    psql = tmp_path / 'psql'
    psql.write_text(_FAKE_PSQL)
    psql.chmod(0o755)
    log = tmp_path / 'psql.jsonl'
    monkeypatch.setenv('AIDEV_DB_SHAPE_PSQL', f'{psql} -X -d "shape copy"')
    monkeypatch.setenv('FAKE_PSQL_LOG', str(log))
    monkeypatch.delenv('FAKE_PSQL_FAIL', raising=False)
    return log


def _apply() -> subprocess.CompletedProcess[str]:
    return subprocess.run([sys.executable, str(SCRIPT)], capture_output=True, text=True, check=False, env=os.environ)


def _sessions(log: Path) -> list[dict[str, Any]]:
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []


def test_each_script_runs_in_its_own_session_after_the_owners_are_restored(fake_psql: Path) -> None:
    result = _apply()

    assert result.returncode == 0, result.stdout + result.stderr
    sessions = _sessions(fake_psql)
    steps = shape_apply.plan()
    assert len(sessions) == len(steps) + 1
    assert all(session['argv'] == ['-X', '-d', 'shape copy'] for session in sessions)
    assert sessions[0]['sql'] == shape_apply.OWNERSHIP_SQL
    for session, (role, path) in zip(sessions[1:], steps, strict=True):
        assert session['sql'].endswith(path.read_text())
        assert '\\set REPTRACKER_SCHEMA reptracker_app' in session['sql']
        owner_preamble = (
            f"SET ROLE hivemind;\nSET search_path TO reptracker_app;\nSET custom.swagger_url = '{SWAGGER_URL}';"
        )
        assert (owner_preamble in session['sql']) == (role == shape_apply.OWNER)


def test_a_failing_script_stops_the_install_naming_it(fake_psql: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv('FAKE_PSQL_FAIL', 'hivemind_endpoints.home(JSON)')

    result = _apply()

    assert result.returncode == 1
    assert (
        'shape apply: hive/db/sql_scripts/postgrest/home.sql failed (exit 3): psql:<stdin>:1: ERROR:  boom'
        in result.stderr
    )
    assert _sessions(fake_psql)[-1]['sql'].endswith((ROOT / 'hive/db/sql_scripts/postgrest/home.sql').read_text())


def test_without_the_shape_psql_it_refuses(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv('AIDEV_DB_SHAPE_PSQL', raising=False)

    result = _apply()

    assert result.returncode == 1
    assert 'AIDEV_DB_SHAPE_PSQL is not set' in result.stderr
