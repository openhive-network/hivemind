#!/usr/bin/env python3
"""What the shared hivemind fixture is keyed by, and how a run picks from it.

Read by the provider's seeder (.aidev/shared-hivemind/) and by the `tavern`
step (.aidev/hivemind_tavern.py), so both agree on the key.

    shared_fixture.py revision FILE|-

prints the schema revision FILE (update_db_patchlevel.sql; `-` for stdin)
installs, and exits 1 when it names none.
"""

import re
import secrets
import sys
from collections.abc import Iterable
from dataclasses import dataclass
from datetime import UTC, datetime

PATCHLEVEL_SQL = "hive/db/sql_scripts/upgrade/update_db_patchlevel.sql"

# The pattern CI's POSTGREST_ONLY_CHANGE path greps the patch level with
# (`grep -oP "'\K[a-f0-9]{40}(?=')" | tail -1`): the last quoted 40-hex hash.
_REVISION_RE = re.compile(r"'([a-f0-9]{40})(?=')")

# What hivemind_shared._run_database_name (admin.sql) accepts.
RUN_ID_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{0,47}$")


@dataclass(frozen=True)
class Template:
    revision: str
    database: str


def revision(patchlevel_sql: str) -> str | None:
    """The schema revision a patch-level script installs: its last quoted
    40-hex hash, or None when it names none."""
    found = _REVISION_RE.findall(patchlevel_sql)
    return found[-1] if found else None


def select_template(templates: Iterable[Template], wanted: str) -> Template | None:
    """The template seeded for revision `wanted`, or None: a template of any
    other revision was synced by other indexer/schema code and never stands in."""
    return next((t for t in templates if t.revision == wanted), None)


def miss_message(wanted: str, requested: bool) -> str:
    """The skip reason when no template matches `wanted`."""
    if requested:
        return f"no hivemind fixture for schema revision {wanted}; seeding requested"
    return f"no hivemind fixture for schema revision {wanted}; seeding not requested (the checkout has no commit)"


def new_run_id(prefix: str, now: datetime | None = None) -> str:
    """A run id unique across concurrent runs, readable in health() and the
    reaper's log: <prefix>-<UTC timestamp>-<random hex>."""
    stamp = (now or datetime.now(UTC)).strftime("%Y%m%dt%H%M%S")
    run_id = f"{prefix}-{stamp}-{secrets.token_hex(4)}"
    if not RUN_ID_RE.match(run_id):
        raise ValueError(f"prefix {prefix!r} makes run id {run_id!r}, which the clone API refuses")
    return run_id


def _main(argv: list[str]) -> int:
    if len(argv) != 3 or argv[1] != "revision":
        print(f"usage: {argv[0]} revision FILE|-", file=sys.stderr)
        return 2
    if argv[2] == "-":
        text = sys.stdin.read()
    else:
        with open(argv[2], encoding="utf-8") as handle:
            text = handle.read()
    found = revision(text)
    if found is None:
        print(f"{argv[2]} names no schema revision", file=sys.stderr)
        return 1
    print(found)
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv))
