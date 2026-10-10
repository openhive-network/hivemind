import subprocess
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts' / 'ci' / 'pick_compatible_cache.sh'
HAF = 'a1b2c3d4'
CURRENT = '2a6576357f9a0a55fafd7e6169f32ed65663cb50'
OLDER = '1111111111111111111111111111111111111111'


def _run(*args: str, stdin: str = '') -> subprocess.CompletedProcess[str]:
    return subprocess.run(['bash', str(SCRIPT), *args], input=stdin, check=True, capture_output=True, text=True)


def _patchlevel(tmp_path: Path, revision: str) -> Path:
    file = tmp_path / 'update_db_patchlevel.sql'
    file.write_text(f"values\n (now(), '{revision}') -- merge request\n) ds (patch_date, patch_revision)\n")
    return file


@pytest.fixture
def nfs(tmp_path: Path) -> Path:
    path = tmp_path / 'nfs' / 'haf_hivemind_sync'
    path.mkdir(parents=True)
    return path


def _cache(nfs: Path, key: str, created_at: str, revision: str | None, tmp_path: Path) -> None:
    (nfs / f'{key}.tar').write_bytes(b'')
    meta = nfs / key
    meta.mkdir()
    (meta / '.metadata').write_text(
        f'{{\n    "cache_key": "{key}",\n    "created_at": "{created_at}",\n    "size_bytes": 1\n}}\n'
    )
    if revision is not None:
        _run('record', str(_patchlevel(tmp_path, revision)), str(nfs), key)


def _listing(*keys: str) -> str:
    lines = ['=== Local Caches (/cache) ===', '  haf_hivemind_sync_other - 1G - 2026-10-01 10:00:00', '']
    lines += ['=== NFS Caches (/nfs/ci-cache) ===']
    lines += [f'  {key} - 30G - 2026-10-01T10:00:00+00:00' for key in keys]
    return '\n'.join(lines) + '\n'


def _pick(nfs: Path, listing: str, revision: str = CURRENT) -> str:
    return _run('pick', HAF, revision, str(nfs), stdin=listing).stdout.strip()


def test_revision_reads_the_patch_level_script(tmp_path: Path) -> None:
    assert _run('revision', str(_patchlevel(tmp_path, CURRENT))).stdout.strip() == CURRENT


def test_picks_the_newest_cache_with_the_expected_revision(nfs: Path, tmp_path: Path) -> None:
    # Alphabetical order puts the oldest first: the pick must not depend on listing order.
    _cache(nfs, f'{HAF}_aaaaaaaa', '2026-10-01T08:00:00+00:00', CURRENT, tmp_path)
    _cache(nfs, f'{HAF}_bbbbbbbb', '2026-10-03T08:00:00+02:00', CURRENT, tmp_path)
    _cache(nfs, f'{HAF}_cccccccc', '2026-10-02T08:00:00+00:00', CURRENT, tmp_path)

    result = _run(
        'pick', HAF, CURRENT, str(nfs), stdin=_listing(f'{HAF}_aaaaaaaa', f'{HAF}_bbbbbbbb', f'{HAF}_cccccccc')
    )

    assert result.stdout.strip() == f'{HAF}_bbbbbbbb'
    assert f'Chosen cache {HAF}_bbbbbbbb: schema revision {CURRENT}, created 2026-10-03T06:00:00Z' in result.stderr


def test_ignores_a_newer_cache_with_a_different_revision(nfs: Path, tmp_path: Path) -> None:
    _cache(nfs, f'{HAF}_aaaaaaaa', '2026-10-01T08:00:00+00:00', CURRENT, tmp_path)
    _cache(nfs, f'{HAF}_bbbbbbbb', '2026-10-05T08:00:00+00:00', OLDER, tmp_path)
    _cache(nfs, f'{HAF}_cccccccc', '2026-10-06T08:00:00+00:00', None, tmp_path)

    assert _pick(nfs, _listing(f'{HAF}_aaaaaaaa', f'{HAF}_bbbbbbbb', f'{HAF}_cccccccc')) == f'{HAF}_aaaaaaaa'


def test_ignores_caches_of_another_haf_commit(nfs: Path, tmp_path: Path) -> None:
    _cache(nfs, 'ffffffff_aaaaaaaa', '2026-10-05T08:00:00+00:00', CURRENT, tmp_path)

    assert _pick(nfs, _listing('ffffffff_aaaaaaaa')) == ''


def test_returns_none_when_no_revision_matches(nfs: Path, tmp_path: Path) -> None:
    _cache(nfs, f'{HAF}_aaaaaaaa', '2026-10-01T08:00:00+00:00', OLDER, tmp_path)
    _cache(nfs, f'{HAF}_bbbbbbbb', '2026-10-02T08:00:00+00:00', None, tmp_path)

    result = _run('pick', HAF, CURRENT, str(nfs), stdin=_listing(f'{HAF}_aaaaaaaa', f'{HAF}_bbbbbbbb'))

    assert result.stdout == ''
    assert f'No cache for HAF commit {HAF} has schema revision {CURRENT}' in result.stderr


def test_returns_none_without_an_expected_revision(nfs: Path, tmp_path: Path) -> None:
    _cache(nfs, f'{HAF}_aaaaaaaa', '2026-10-01T08:00:00+00:00', CURRENT, tmp_path)

    assert _pick(nfs, _listing(f'{HAF}_aaaaaaaa'), revision='') == ''
