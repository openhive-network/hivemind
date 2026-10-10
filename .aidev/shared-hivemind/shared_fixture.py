#!/usr/bin/env python3
"""What the shared hivemind fixture is keyed by, and how a run picks from it.

Read by the provider's seeder (.aidev/shared-hivemind/) and by the `tavern`
step (.aidev/hivemind_tavern.py), so both agree on the key: a template is
seeded for a (schema revision, sync recipe) pair.

    shared_fixture.py revision FILE|-

prints the schema revision FILE (update_db_patchlevel.sql; `-` for stdin)
installs, and exits 1 when it names none.

    shared_fixture.py recipe tree DIR HAF_COMMIT
    shared_fixture.py recipe commit GIT_DIR COMMIT HAF_COMMIT

prints the sync recipe of the checkout DIR (its tracked files as they are on
disk) or of COMMIT in the repository GIT_DIR, synced on HAF_COMMIT.

    shared_fixture.py retire KEEP

reads `<revision> <recipe> <template> <live clones>` lines, newest template
first (hivemind_shared.health()), and prints the templates past the newest
KEEP of their revision that no live clone uses.
"""

import argparse
import hashlib
import os
import re
import secrets
import subprocess
import sys
from collections.abc import Iterable
from dataclasses import dataclass
from datetime import UTC, datetime

PATCHLEVEL_SQL = "hive/db/sql_scripts/upgrade/update_db_patchlevel.sql"
PROJECT_YAML = ".aidev/project.yaml"

# The pattern CI's POSTGREST_ONLY_CHANGE path greps the patch level with
# (`grep -oP "'\K[a-f0-9]{40}(?=')" | tail -1`): the last quoted 40-hex hash.
_REVISION_RE = re.compile(r"'([a-f0-9]{40})(?=')")

# What hivemind_shared._run_database_name (admin.sql) accepts.
RUN_ID_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{0,47}$")

# What hivemind_shared._check_recipe (admin.sql) accepts.
RECIPE_RE = re.compile(r"^[0-9a-f]{64}$")

_HAF_COMMIT_RE = re.compile(r"^\s*HAF_FIXTURE_COMMIT:\s*[\"']?([0-9a-f]{40})[\"']?\s*$", re.MULTILINE)
_SHA_RE = re.compile(r"^[0-9a-f]{40}$")

# The files whose contents decide what a seed syncs (seed.sh runs them), and
# the submodules (reputation_tracker, hafah) by the commit the tree pins.
RECIPE_PATHS = (
    ".aidev/shared-hivemind/seed.sh",
    "hafah",
    "hive/db",
    "hive/indexer",
    "hive/utils",
    "mock_data",
    "reputation_tracker",
    "scripts/ci/add-mocks-to-db.sh",
    "scripts/ci/wrapper_for_app_next_block.sql",
    "scripts/install_app.sh",
    "scripts/install_app.sql",
    "scripts/setup_postgres.sh",
)
# CI's POSTGREST_ONLY_PATTERNS: the tavern step reloads these into every clone,
# so they never decide which template a tree needs.
_RECIPE_EXCLUDED = ("hive/db/sql_scripts/postgrest/", "hive/db/sql_scripts/endpoints/")
_GITLINK_MODE = "160000"
_SYMLINK_MODE = "120000"


class RecipeError(RuntimeError):
    """git could not list the recipe's files."""


@dataclass(frozen=True)
class Template:
    revision: str
    recipe: str
    database: str


def revision(patchlevel_sql: str) -> str | None:
    """The schema revision a patch-level script installs: its last quoted
    40-hex hash, or None when it names none."""
    found = _REVISION_RE.findall(patchlevel_sql)
    return found[-1] if found else None


def haf_fixture_commit(project_yaml: str) -> str | None:
    """The HAF commit project.yaml's shared hivemind seeds on
    (HAF_FIXTURE_COMMIT), or None when it names none."""
    found = _HAF_COMMIT_RE.search(project_yaml)
    return found.group(1) if found else None


def _in_recipe(path: str) -> bool:
    return not path.startswith(_RECIPE_EXCLUDED)


def _recipe(entries: Iterable[tuple[str, str]], haf_commit: str) -> str:
    if not _SHA_RE.match(haf_commit):
        raise ValueError(f"HAF commit must be 40 lowercase hex digits, got {haf_commit!r}")
    digest = hashlib.sha256(f"haf {haf_commit}\n".encode())
    for path, object_id in sorted(entries):
        digest.update(f"{path} {object_id}\n".encode())
    return digest.hexdigest()


def _git(args: list[str]) -> str:
    proc = subprocess.run(["git", *args], capture_output=True, text=True)
    if proc.returncode != 0:
        raise RecipeError(f"git {' '.join(args[:3])}: {proc.stderr.strip()}")
    return proc.stdout


def _blob_id(data: bytes) -> str:
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def recipe_of_tree(root: str, haf_commit: str) -> str:
    """The sync recipe of the checkout `root`: its tracked recipe files as they
    are on disk (uncommitted edits count, untracked files do not), the
    submodule commits its index pins, and `haf_commit`. Equals
    recipe_of_commit of a clean checkout's HEAD. Raises RecipeError when git
    cannot list the files."""
    entries = []
    for record in _git(["-C", root, "ls-files", "-s", "-z", "--", *RECIPE_PATHS]).split("\0"):
        if not record:
            continue
        info, path = record.split("\t", 1)
        mode, object_id, _stage = info.split(" ")
        if not _in_recipe(path):
            continue
        full = os.path.join(root, path)
        if mode == _GITLINK_MODE:
            entries.append((path, object_id))
        elif mode == _SYMLINK_MODE and os.path.islink(full):
            entries.append((path, _blob_id(os.fsencode(os.readlink(full)))))
        elif os.path.isfile(full):
            with open(full, "rb") as handle:
                entries.append((path, _blob_id(handle.read())))
    return _recipe(entries, haf_commit)


def recipe_of_commit(git_dir: str, commit: str, haf_commit: str) -> str:
    """The sync recipe of `commit` in the repository `git_dir` (bare or not)
    on `haf_commit`. Raises RecipeError when git cannot list its tree."""
    entries = []
    for record in _git(["--git-dir", git_dir, "ls-tree", "-r", "-z", commit, "--", *RECIPE_PATHS]).split("\0"):
        if not record:
            continue
        info, path = record.split("\t", 1)
        _mode, _type, object_id = info.split(" ")
        if _in_recipe(path):
            entries.append((path, object_id))
    return _recipe(entries, haf_commit)


def select_template(templates: Iterable[Template], revision: str, recipe: str) -> Template | None:
    """The template to clone for (`revision`, `recipe`), from `templates` newest
    first: the one seeded for both, else the newest of the revision (synced by
    another recipe, but schema-compatible), else None. A template of any other
    revision was synced by other indexer/schema code and never stands in."""
    same_revision = [t for t in templates if t.revision == revision]
    return next((t for t in same_revision if t.recipe == recipe), same_revision[0] if same_revision else None)


def miss_message(wanted: str, requested: bool) -> str:
    """The skip reason when no template matches `wanted`."""
    if requested:
        return f"no hivemind fixture for schema revision {wanted}; seeding requested"
    return f"no hivemind fixture for schema revision {wanted}; seeding not requested (the checkout has no commit)"


def fallback_message(template: Template, recipe: str, requested: bool) -> str:
    """The advisory when `template` stands in for the tree's `recipe`."""
    seeding = "seeding requested" if requested else "seeding not requested (the checkout has no commit)"
    return (
        f"advisory: no hivemind fixture for sync recipe {recipe[:12]} of schema revision {template.revision}; "
        f"using {template.database}, synced by recipe {template.recipe[:12]}; {seeding}"
    )


def retire(templates: Iterable[tuple[Template, int]], keep: int) -> list[Template]:
    """The templates to drop, from (template, live clones) pairs newest first:
    those past the newest `keep` of their revision with no live clone."""
    if keep < 1:
        raise ValueError(f"keep must be at least 1, got {keep}")
    seen: dict[str, int] = {}
    retired = []
    for template, live in templates:
        seen[template.revision] = seen.get(template.revision, 0) + 1
        if seen[template.revision] > keep and live == 0:
            retired.append(template)
    return retired


def new_run_id(prefix: str, now: datetime | None = None) -> str:
    """A run id unique across concurrent runs, readable in health() and the
    reaper's log: <prefix>-<UTC timestamp>-<random hex>."""
    stamp = (now or datetime.now(UTC)).strftime("%Y%m%dt%H%M%S")
    run_id = f"{prefix}-{stamp}-{secrets.token_hex(4)}"
    if not RUN_ID_RE.match(run_id):
        raise ValueError(f"prefix {prefix!r} makes run id {run_id!r}, which the clone API refuses")
    return run_id


def _main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog=argv[0])
    commands = parser.add_subparsers(dest="command", required=True)
    revision_cmd = commands.add_parser("revision")
    revision_cmd.add_argument("file")
    recipe_cmd = commands.add_parser("recipe").add_subparsers(dest="source", required=True)
    tree_cmd = recipe_cmd.add_parser("tree")
    tree_cmd.add_argument("dir")
    tree_cmd.add_argument("haf_commit")
    commit_cmd = recipe_cmd.add_parser("commit")
    commit_cmd.add_argument("git_dir")
    commit_cmd.add_argument("commit")
    commit_cmd.add_argument("haf_commit")
    retire_cmd = commands.add_parser("retire")
    retire_cmd.add_argument("keep", type=int)
    args = parser.parse_args(argv[1:])

    if args.command == "revision":
        if args.file == "-":
            text = sys.stdin.read()
        else:
            with open(args.file, encoding="utf-8") as handle:
                text = handle.read()
        found = revision(text)
        if found is None:
            print(f"{args.file} names no schema revision", file=sys.stderr)
            return 1
        print(found)
    elif args.command == "recipe":
        try:
            if args.source == "tree":
                print(recipe_of_tree(args.dir, args.haf_commit))
            else:
                print(recipe_of_commit(args.git_dir, args.commit, args.haf_commit))
        except (RecipeError, ValueError) as err:
            print(err, file=sys.stderr)
            return 1
    else:
        rows = [line.split() for line in sys.stdin if line.strip()]
        for template in retire(((Template(*row[:3]), int(row[3])) for row in rows), args.keep):
            print(template.database)
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv))
