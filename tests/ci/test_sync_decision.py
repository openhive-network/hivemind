import os
import subprocess
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts' / 'ci' / 'sync_decision.sh'
SKIP_PATTERNS = r'^\.aidev/|^tests/|^docs/|\.md$|^README|^CHANGELOG|^LICENSE|^CLAUDE\.md$|^\.gitlab-ci\.yml$'
POSTGREST_PATTERNS = r'^hive/db/sql_scripts/postgrest/|^hive/db/sql_scripts/endpoints/'

FULL = {'AUTO_SKIP_SYNC': 'false', 'POSTGREST_ONLY_CHANGE': 'false'}
POSTGREST_ONLY = {'AUTO_SKIP_SYNC': 'false', 'POSTGREST_ONLY_CHANGE': 'true'}
SKIP = {'AUTO_SKIP_SYNC': 'true', 'POSTGREST_ONLY_CHANGE': 'false'}


def _git(repo: Path, *args: str) -> str:
    return subprocess.run(['git', '-C', str(repo), *args], check=True, capture_output=True, text=True).stdout.strip()


@pytest.fixture
def repo(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    for role in ('AUTHOR', 'COMMITTER'):
        monkeypatch.setenv(f'GIT_{role}_NAME', 'test')
        monkeypatch.setenv(f'GIT_{role}_EMAIL', 'test@example.com')
    _git(tmp_path, 'init', '-q')
    _commit(tmp_path, ['base.txt'])
    return tmp_path


def _commit(repo: Path, paths: list[str], trailer: str | None = None) -> None:
    for path in paths:
        file = repo / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(f'{file.read_text() if file.exists() else ""}{path}\n')
        _git(repo, 'add', path)
    message = 'change' if trailer is None else f'change\n\nHivemind-Sync: {trailer}'
    _git(repo, 'commit', '-q', '-m', message)


def _decision(repo: Path, base: str, ref: str = 'feature', auto_skip: str = 'false') -> dict[str, str]:
    result = subprocess.run(
        ['bash', str(SCRIPT), base, 'HEAD'],
        cwd=repo,
        env={
            **os.environ,
            'AUTO_SKIP_SYNC': auto_skip,
            'HAF_APP_SKIP_PATTERNS': SKIP_PATTERNS,
            'POSTGREST_ONLY_PATTERNS': POSTGREST_PATTERNS,
            'CI_COMMIT_REF_NAME': ref,
        },
        check=True,
        capture_output=True,
        text=True,
    )
    return dict(line.split('=', 1) for line in result.stdout.splitlines())


# (commits as (paths, trailer), ref, pattern-pass AUTO_SKIP_SYNC, expected)
CASES = {
    'not-required schema.py and hive/utils -> postgrest-only': (
        [
            (['hive/db/schema.py', 'hive/db/sql_scripts/postgrest/a.sql'], 'not-required'),
            (['hive/utils/x.py'], 'not-required'),
        ],
        'feature',
        'false',
        POSTGREST_ONLY,
    ),
    'not-required with a guarded indexer file -> full': (
        [(['hive/indexer/posts.py', 'hive/utils/x.py'], 'not-required')],
        'feature',
        'false',
        FULL,
    ),
    'not-required with massive_sync.sql -> full': (
        [(['hive/db/sql_scripts/massive_sync.sql'], 'not-required')],
        'feature',
        'false',
        FULL,
    ),
    'not-required with schema DDL -> full': (
        [(['hive/db/sql_scripts/schema/tables.sql'], 'not-required')],
        'feature',
        'false',
        FULL,
    ),
    'not-required with a reason (as AIDEV writes it) -> postgrest-only': (
        [
            (
                ['hive/db/schema.py', 'hive/db/sql_scripts/postgrest/a.sql'],
                'not-required — only registers a PostgREST script',
            )
        ],
        'feature',
        'false',
        POSTGREST_ONLY,
    ),
    'not-required whose reason has commas and the word required -> postgrest-only': (
        [
            (
                ['hive/db/schema.py'],
                'not-required — registers a script, required by nothing at sync time, docs too',
            )
        ],
        'feature',
        'false',
        POSTGREST_ONLY,
    ),
    'required with a reason -> full': (
        [(['hive/db/sql_scripts/postgrest/a.sql'], 'required — changes a table')],
        'feature',
        'false',
        FULL,
    ),
    'required forces full even for docs-only': (
        [(['docs/a.md'], 'required')],
        'feature',
        'true',
        FULL,
    ),
    'required in any commit overrides not-required': (
        [(['hive/db/sql_scripts/postgrest/a.sql'], 'not-required'), (['README.md'], 'required')],
        'feature',
        'false',
        FULL,
    ),
    'no trailers, postgrest only -> postgrest-only as today': (
        [(['hive/db/sql_scripts/postgrest/a.sql', 'tests/x.py'], None)],
        'feature',
        'false',
        POSTGREST_ONLY,
    ),
    'no trailers, schema.py -> full as today': (
        [(['hive/db/schema.py', 'hive/db/sql_scripts/postgrest/a.sql'], None)],
        'feature',
        'false',
        FULL,
    ),
    'no trailers, docs only -> skip as today': (
        [(['docs/a.md'], None)],
        'feature',
        'true',
        SKIP,
    ),
    'file also changed by an untrailered commit -> full': (
        [(['hive/utils/x.py'], 'not-required'), (['hive/utils/x.py'], None)],
        'feature',
        'false',
        FULL,
    ),
    'develop ignores not-required -> full as today': (
        [(['hive/db/schema.py'], 'not-required')],
        'develop',
        'false',
        FULL,
    ),
    'master ignores not-required -> full as today': (
        [(['hive/utils/x.py'], 'not-required')],
        'master',
        'false',
        FULL,
    ),
    'develop still honours required': (
        [(['docs/a.md'], 'required')],
        'develop',
        'true',
        FULL,
    ),
}


@pytest.mark.parametrize(('commits', 'ref', 'auto_skip', 'expected'), CASES.values(), ids=CASES.keys())
def test_sync_decision(
    repo: Path, commits: list[tuple[list[str], str | None]], ref: str, auto_skip: str, expected: dict[str, str]
) -> None:
    base = _git(repo, 'rev-parse', 'HEAD')
    for paths, trailer in commits:
        _commit(repo, paths, trailer)

    assert _decision(repo, base, ref, auto_skip) == expected


def test_not_required_commits_merged_from_a_branch_still_count(repo: Path) -> None:
    base = _git(repo, 'rev-parse', 'HEAD')
    _git(repo, 'checkout', '-q', '-b', 'side')
    _commit(repo, ['hive/utils/x.py'], 'not-required')
    _git(repo, 'checkout', '-q', '-')
    _commit(repo, ['hive/db/sql_scripts/postgrest/a.sql'])
    _git(repo, 'merge', '-q', '--no-ff', 'side', '-m', 'merge')

    assert _decision(repo, base) == POSTGREST_ONLY
