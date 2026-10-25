import json
import os
import re
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


def _script_loads(log: Path) -> list[list[str]]:
    return [call for call in _loaded(log) if '-f' in call]


def _file_of(call: list[str]) -> str:
    return call[call.index('-f') + 1]


def test_every_script_loads_with_the_installers_swagger_url(fake_psql: Path) -> None:
    result = _reload()

    assert result.returncode == 0, result.stdout + result.stderr
    calls = _script_loads(fake_psql)
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
    files = [_file_of(call) for call in _script_loads(fake_psql)]
    assert files
    assert not any(f.endswith(ADMIN_SCRIPT) for f in files)
    assert all(URL in call for call in _loaded(fake_psql))


# A PostgREST whose schema cache holds the probe functions that existed at the last NOTIFY in
# the fake psql log; FAKE_CURL_STALE makes it ignore NOTIFY.
_FAKE_CURL = '''#!/usr/bin/env python3
import json, os, re, sys
cache, db = set(), set()
with open(os.environ['FAKE_PSQL_LOG']) as log:
    for line in log:
        sql = ' '.join(json.loads(line))
        if m := re.search(r'CREATE FUNCTION hivemind_endpoints\\.(\\w+)\\(', sql):
            db.add(m.group(1))
        if m := re.search(r'DROP FUNCTION (?:IF EXISTS )?hivemind_endpoints\\.(\\w+)\\(', sql):
            db.discard(m.group(1))
        if "NOTIFY pgrst, 'reload schema'" in sql and not os.environ.get('FAKE_CURL_STALE'):
            cache = set(db)
url = sys.argv[-1]
with open(os.environ['FAKE_CURL_LOG'], 'a') as log:
    log.write(url + '\\n')
print('200' if url.rsplit('/', 1)[-1] in cache else '404', end='')
'''

POSTGREST = 'http://postgrest:8080'
NOTIFY = "NOTIFY pgrst, 'reload schema'"


@pytest.fixture
def fake_postgrest(fake_psql: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    curl = tmp_path / 'bin' / 'curl'
    curl.write_text(_FAKE_CURL)
    curl.chmod(0o755)
    log = tmp_path / 'curl.log'
    monkeypatch.setenv('FAKE_CURL_LOG', str(log))
    monkeypatch.delenv('FAKE_CURL_STALE', raising=False)
    return log


def _sql_of(call: list[str]) -> str:
    return call[call.index('-c') + 1]


def test_the_schema_cache_reload_is_notified_after_every_script(fake_psql: Path) -> None:
    result = _reload()

    assert result.returncode == 0, result.stdout + result.stderr
    calls = _loaded(fake_psql)
    assert _sql_of(calls[-1]) == NOTIFY
    assert all('-f' in call for call in calls[:-1])


def test_waits_until_postgrest_serves_a_function_created_after_the_reload(
    fake_psql: Path, fake_postgrest: Path
) -> None:
    result = _reload(f'--postgrest-url={POSTGREST}')

    assert result.returncode == 0, result.stdout + result.stderr
    calls = _loaded(fake_psql)
    last_load = max(i for i, call in enumerate(calls) if '-f' in call)
    statements = [_sql_of(call) for call in calls[last_load + 1 :]]
    probe = re.fullmatch(r'CREATE FUNCTION (hivemind_endpoints\.(\w+))\(\) .*', statements[0])
    assert probe
    assert statements[1:] == [NOTIFY, f'DROP FUNCTION {probe.group(1)}()', NOTIFY]
    assert set(fake_postgrest.read_text().split()) == {f'{POSTGREST}/rpc/{probe.group(2)}'}
    assert 'OK: PostgREST serves the reloaded functions' in result.stdout


def test_a_schema_cache_that_never_reloads_fails_the_reload(
    fake_psql: Path, fake_postgrest: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv('FAKE_CURL_STALE', '1')

    result = _reload(f'--postgrest-url={POSTGREST}', '--postgrest-timeout=1')

    assert result.returncode != 0
    assert f'ERROR: PostgREST at {POSTGREST} did not reload its schema cache within 1s' in result.stdout
    assert 'last HTTP status: 404' in result.stdout
    assert re.fullmatch(r'DROP FUNCTION IF EXISTS hivemind_endpoints\.\w+\(\)', _sql_of(_loaded(fake_psql)[-1]))
    assert 'reloaded successfully' not in result.stdout
