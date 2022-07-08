from datetime import datetime
from datetime import timezone
from typing import Final

import git


class VersionProvider:
    """Static class to provide version and git revision information"""

    repo = git.Repo(search_parent_directories=True)

    @classmethod
    def latest_tag_on_current_branch(cls) -> str:
        version = cls.repo.git.describe('--tags', '--abbrev=0')
        return version

    @classmethod
    def git_revision(cls, short: bool = False) -> str:
        sha = cls.repo.head.object.hexsha
        return sha[:8] if short else sha

    @classmethod
    def git_revision_datetime(cls) -> datetime:
        git_datetime = cls.repo.head.object.committed_datetime
        return git_datetime.astimezone(timezone.utc)


VERSION: Final[str] = VersionProvider.latest_tag_on_current_branch()
GIT_REVISION: Final[str] = VersionProvider.git_revision()
GIT_DATE: Final[datetime] = VersionProvider.git_revision_datetime()
