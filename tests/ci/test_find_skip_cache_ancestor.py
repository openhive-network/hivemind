import os
import subprocess
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts' / 'ci' / 'find_skip_cache_ancestor.sh'
SKIP_PATTERNS = r'^tests/|^docs/|\.md$|^\.gitlab-ci\.yml$'


def _git(repo: Path, *args: str) -> str:
    return subprocess.run(['git', '-C', str(repo), *args], check=True, capture_output=True, text=True).stdout.strip()


@pytest.fixture
def repo(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    for role in ('AUTHOR', 'COMMITTER'):
        monkeypatch.setenv(f'GIT_{role}_NAME', 'test')
        monkeypatch.setenv(f'GIT_{role}_EMAIL', 'test@example.com')
    _git(tmp_path, 'init', '-q')
    return tmp_path


def _commit(repo: Path, path: str) -> str:
    file = repo / path
    file.parent.mkdir(parents=True, exist_ok=True)
    file.write_text(path)
    _git(repo, 'add', path)
    _git(repo, 'commit', '-q', '-m', path)
    return _git(repo, 'rev-parse', 'HEAD')[:8]


def _candidates(repo: Path) -> list[str]:
    result = subprocess.run(
        ['bash', str(SCRIPT)],
        cwd=repo,
        env={**os.environ, 'HAF_APP_SKIP_PATTERNS': SKIP_PATTERNS},
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.split()


def test_docs_commit_on_code_commit_yields_the_code_commit(repo: Path) -> None:
    _commit(repo, 'hive/old.py')
    code = _commit(repo, 'hive/indexer.py')
    _commit(repo, 'docs/guide.md')

    assert _candidates(repo) == [code]


def test_docs_docs_code_yields_both_docs_parents_and_the_code_commit_only(repo: Path) -> None:
    _commit(repo, 'hive/old.py')
    code = _commit(repo, 'hive/indexer.py')
    docs1 = _commit(repo, 'docs/a.md')
    docs2 = _commit(repo, 'tests/test_a.py')
    _commit(repo, '.gitlab-ci.yml')

    assert _candidates(repo) == [docs2, docs1, code]


def test_code_change_at_head_yields_nothing(repo: Path) -> None:
    _commit(repo, 'hive/old.py')
    _commit(repo, 'docs/a.md')
    _commit(repo, 'hive/indexer.py')

    assert _candidates(repo) == []
