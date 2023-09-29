from dataclasses import dataclass
from pathlib import Path
from typing import Final, Literal

from hive import _version

import dunamai


@dataclass
class _Replacable:
    filepath: Path
    pattern: str
    old_value: str
    new_value: str


class MetadataUpdater:
    _GIT_REVISION_LOCATION: Final[Path] = Path(_version.__file__)
    _GIT_REVISION_DATE_LOCATION: Final[Path] = _GIT_REVISION_LOCATION

    _GIT_REVISION_PATTERN: Final[str] = '__git_revision__ = "{0}"'
    _GIT_REVISION_TIMESTAMP_PATTERN: Final[str] = '__git_revision_date__ = "{0}"'

    _VERSION: Final[dunamai.Version] = dunamai.Version.from_git(full_commit=True)

    @classmethod
    def substitute(cls) -> None:
        cls.__substitute("git_revision")
        cls.__substitute("git_revision_date")

    @classmethod
    def __substitute(cls, what: Literal["git_revision", "git_revision_date"]) -> None:
        if what == "git_revision":
            replacable = _Replacable(
                filepath=cls._GIT_REVISION_LOCATION,
                pattern=cls._GIT_REVISION_PATTERN,
                old_value=_version.__git_revision__,
                new_value=cls.__get_git_revision(),
            )
        elif what == "git_revision_date":
            replacable = _Replacable(
                filepath=cls._GIT_REVISION_DATE_LOCATION,
                pattern=cls._GIT_REVISION_TIMESTAMP_PATTERN,
                old_value=_version.__git_revision_date__,
                new_value=cls.__get_git_revision_date(),
            )
        else:
            raise ValueError(f"Invalid value for `what`: {what}")

        with open(replacable.filepath, "r") as f:
            content = f.read()

        to_replace = replacable.pattern.format(replacable.old_value)
        cls.__assert_to_replace_exists(to_replace, replacable.filepath)

        replace_with = replacable.pattern.format(replacable.new_value)
        new_content = content.replace(to_replace, replace_with)

        with open(replacable.filepath, "w") as f:
            f.write(new_content)

    @staticmethod
    def __assert_to_replace_exists(to_replace: str, filepath: Path) -> None:
        with open(filepath, "r") as f:
            content = f.read()
        assert to_replace in content, f"Could not find `{to_replace}` in `{filepath}`"

    @classmethod
    def __get_git_revision(cls) -> str:
        revision = cls._VERSION.commit
        assert revision is not None, "Could not get git revision"
        return revision

    @classmethod
    def __get_git_revision_date(cls) -> str:
        date = cls._VERSION.timestamp
        assert date is not None, "Could not get git revision date"
        return date.isoformat()


if __name__ == "__main__":
    MetadataUpdater.substitute()
