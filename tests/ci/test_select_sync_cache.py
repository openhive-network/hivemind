import os
import subprocess
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parents[2] / 'scripts' / 'ci'
HAF = 'a1b2c3d4'
REVISION = '2a6576357f9a0a55fafd7e6169f32ed65663cb50'
OTHER_REVISION = '1111111111111111111111111111111111111111'
TYPE = 'haf_hivemind_sync'
HEAD_KEY = f'{HAF}_0000head'
ANCESTOR_KEY = f'{HAF}_ancestor'

# Stands in for common-ci-configuration's cache-manager.sh: `list` prints every
# tar under $NFS/<type>, `get` succeeds (and logs the extraction) for those only.
_FAKE_CACHE_MANAGER = """#!/bin/bash
set -euo pipefail
case "$1" in
  list)
    echo "=== NFS Caches ==="
    for tar in "$NFS/$2"/*.tar; do
      [[ -e "$tar" ]] && echo "  $(basename "$tar" .tar) - 30G - 2026-10-01T10:00:00+00:00"
    done
    ;;
  get)
    [[ -e "$NFS/$2/$3.tar" ]] || { echo "no cache $3" >&2; exit 1; }
    echo "$3 -> $4" >> "$NFS/extracted.log"
    ;;
esac
"""


@pytest.fixture
def nfs(tmp_path: Path) -> Path:
    path = tmp_path / 'nfs'
    (path / TYPE).mkdir(parents=True)
    return path


@pytest.fixture
def cache_manager(tmp_path: Path) -> Path:
    script = tmp_path / 'cache-manager.sh'
    script.write_text(_FAKE_CACHE_MANAGER)
    script.chmod(0o755)
    return script


def _cache(nfs: Path, tmp_path: Path, key: str, created_at: str, revision: str | None) -> None:
    (nfs / TYPE / f'{key}.tar').write_bytes(b'')
    meta = nfs / TYPE / key
    meta.mkdir()
    (meta / '.metadata').write_text(f'{{\n    "cache_key": "{key}",\n    "created_at": "{created_at}"\n}}\n')
    if revision is not None:
        patchlevel = tmp_path / 'update_db_patchlevel.sql'
        patchlevel.write_text(f"values (now(), '{revision}')\n")
        subprocess.run(
            ['bash', str(SCRIPTS / 'pick_compatible_cache.sh'), 'record', str(patchlevel), str(nfs / TYPE), key],
            check=True,
            capture_output=True,
        )


def _select(nfs: Path, cache_manager: Path, *args: str) -> subprocess.CompletedProcess[str]:
    env = {
        **os.environ,
        'NFS': str(nfs),
        'CACHE_MANAGER': str(cache_manager),
        'SYNC_CACHE_TYPE': TYPE,
        'HAF_COMMIT': HAF,
        'DATA_CACHE_NFS_PREFIX': str(nfs),
        'LOCAL_CACHE_ROOT': '/local',
    }
    return subprocess.run(
        ['bash', str(SCRIPTS / 'select_sync_cache.sh'), *args], env=env, check=True, capture_output=True, text=True
    )


def _extracted(nfs: Path) -> list[str]:
    log = nfs / 'extracted.log'
    return log.read_text().splitlines() if log.exists() else []


def test_auto_skip_reuses_the_first_candidate_with_a_cache(nfs: Path, cache_manager: Path, tmp_path: Path) -> None:
    _cache(nfs, tmp_path, ANCESTOR_KEY, '2026-10-01T08:00:00+00:00', REVISION)
    _cache(nfs, tmp_path, f'{HAF}_compatib', '2026-10-05T08:00:00+00:00', REVISION)

    result = _select(nfs, cache_manager, 'auto-skip', REVISION, HEAD_KEY, ANCESTOR_KEY)

    assert result.stdout.strip() == f'reuse {ANCESTOR_KEY}'
    assert _extracted(nfs) == [f'{ANCESTOR_KEY} -> /local/{TYPE}_{ANCESTOR_KEY}']


def test_auto_skip_without_an_ancestor_cache_reloads_into_the_newest_compatible_cache(
    nfs: Path, cache_manager: Path, tmp_path: Path
) -> None:
    _cache(nfs, tmp_path, f'{HAF}_olderone', '2026-10-01T08:00:00+00:00', REVISION)
    _cache(nfs, tmp_path, f'{HAF}_newerone', '2026-10-03T08:00:00+00:00', REVISION)
    _cache(nfs, tmp_path, f'{HAF}_otherrev', '2026-10-06T08:00:00+00:00', OTHER_REVISION)

    result = _select(nfs, cache_manager, 'auto-skip', REVISION, HEAD_KEY, ANCESTOR_KEY)

    assert result.stdout.strip() == f'reload {HAF}_newerone'
    assert f'Chosen cache {HAF}_newerone' in result.stderr
    assert _extracted(nfs) == [f'{HAF}_newerone -> /local/{TYPE}_{HAF}_newerone']


def test_auto_skip_without_any_usable_cache_selects_nothing(nfs: Path, cache_manager: Path, tmp_path: Path) -> None:
    _cache(nfs, tmp_path, f'{HAF}_otherrev', '2026-10-06T08:00:00+00:00', OTHER_REVISION)
    _cache(nfs, tmp_path, 'ffffffff_otherhaf', '2026-10-06T08:00:00+00:00', REVISION)

    result = _select(nfs, cache_manager, 'auto-skip', REVISION, HEAD_KEY, ANCESTOR_KEY)

    assert result.stdout == ''
    assert _extracted(nfs) == []


def test_auto_skip_without_a_schema_revision_never_reloads(nfs: Path, cache_manager: Path, tmp_path: Path) -> None:
    _cache(nfs, tmp_path, f'{HAF}_compatib', '2026-10-05T08:00:00+00:00', REVISION)

    assert _select(nfs, cache_manager, 'auto-skip', '', HEAD_KEY).stdout == ''


def test_compatible_reloads_into_the_newest_compatible_cache(nfs: Path, cache_manager: Path, tmp_path: Path) -> None:
    _cache(nfs, tmp_path, HEAD_KEY, '2026-10-01T08:00:00+00:00', OTHER_REVISION)
    _cache(nfs, tmp_path, f'{HAF}_compatib', '2026-10-02T08:00:00+00:00', REVISION)

    assert _select(nfs, cache_manager, 'compatible', REVISION).stdout.strip() == f'reload {HAF}_compatib'
