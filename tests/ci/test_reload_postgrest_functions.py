import json
import os
import subprocess
from pathlib import Path

import pytest

from hive.conf import SWAGGER_URL

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts' / 'ci' / 'reload-postgrest-functions.sh'
URL = 'postgresql://hivemind@db:5432/haf_block_log'
ADMIN_SCRIPT = 'postgrest/utilities/preprocess_search_query.sql'

# Records each call's arguments; exits 3 for the file named by FAKE_PSQL_FAIL.
_FAKE_PSQL = '''#!/usr/bin/env python3
import json, os, sys
with open(os.environ['FAKE_PSQL_LOG'], 'a') as log:
    log.write(json.dumps(sys.argv[1:]) + '\\n')
fail = os.environ.get('FAKE_PSQL_FAIL')
if fail and any(arg.endswith(fail) for arg in sys.argv[1:]):
    print(f'psql:{fail}:1: ERROR:  boom', file=sys.stderr)
    sys.exit(3)
'''


@pytest.fixture
def fake_psql(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    bin_dir = tmp_path / 'bin'
    bin_dir.mkdir()
    (bin_dir / 'psql').write_text(_FAKE_PSQL)
    (bin_dir / 'psql').chmod(0o755)
    log = tmp_path / 'psql.jsonl'
    monkeypatch.setenv('PATH', f'{bin_dir}{os.pathsep}{os.environ["PATH"]}')
    monkeypatch.setenv('FAKE_PSQL_LOG', str(log))
    monkeypatch.delenv('FAKE_PSQL_FAIL', raising=False)
    return log


def _reload(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ['bash', str(SCRIPT), f'--postgres-url={URL}', *args], capture_output=True, text=True, check=False
    )


def _loaded(log: Path) -> list[list[str]]:
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []


def _file_of(call: list[str]) -> str:
    return call[call.index('-f') + 1]


def test_every_script_loads_with_the_installers_swagger_url(fake_psql: Path) -> None:
    result = _reload()

    assert result.returncode == 0, result.stdout + result.stderr
    calls = _loaded(fake_psql)
    files = [_file_of(call) for call in calls]
    assert files[0].endswith(ADMIN_SCRIPT)
    assert any(f.endswith('endpoints/endpoint_schema.sql') for f in files)
    for call in calls:
        set_at = call.index('-c')
        assert call[set_at + 1] == f"SET custom.swagger_url = '{SWAGGER_URL}'"
        assert set_at < call.index('-f')
        assert call[call.index('-v') + 1] == 'ON_ERROR_STOP=on'


def test_a_failing_script_fails_the_reload_naming_it(fake_psql: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv('FAKE_PSQL_FAIL', 'endpoints/endpoint_schema.sql')

    result = _reload()

    assert result.returncode != 0
    assert 'ERROR: Failed to load endpoints/endpoint_schema.sql' in result.stdout
    assert _file_of(_loaded(fake_psql)[-1]).endswith('endpoints/endpoint_schema.sql')
    assert 'reloaded successfully' not in result.stdout


def test_a_failing_admin_script_fails_the_reload(fake_psql: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv('FAKE_PSQL_FAIL', ADMIN_SCRIPT)

    result = _reload()

    assert result.returncode != 0
    assert f'ERROR: Failed to load {ADMIN_SCRIPT}' in result.stdout
    assert len(_loaded(fake_psql)) == 1


def test_skip_admin_scripts_loads_only_the_postgrest_scripts(fake_psql: Path) -> None:
    result = _reload('--skip-admin-scripts')

    assert result.returncode == 0, result.stdout + result.stderr
    files = [_file_of(call) for call in _loaded(fake_psql)]
    assert files
    assert not any(f.endswith(ADMIN_SCRIPT) for f in files)
    assert all(URL in call for call in _loaded(fake_psql))
