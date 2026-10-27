#!/usr/bin/env python3
"""Install this tree's hivemind database code onto a copy of the pinned shape.

    shape_apply.py [--list]

`performance.shape.apply` in .aidev/project.yaml (aidev's `db shape check`,
`apply`, `compare`). The shape already holds production's hivemind install, so
the tree's code goes on the way `hive upgrade_schema` puts it on an installed
database (DbState.initialize): scripts/install_app.sql, then perform_db_upgrade's
scripts and the admin-level scripts, then setup_runtime_code's scripts as the
hivemind role with the reputation_tracker search path and the swagger URL it sets.
The lists are read from hive/db/schema.py (and postgrest/load_order.sql), not
copied, so a script added there is applied here too.

A shape keeps no owners (its objects belong to postgres), so the copy first gets
back the source's (OWNERSHIP_SQL): the hivemind role owns its three schemas and
everything in them but the untrusted-language functions, and its HAF context's
table and sequence. Without that the scripts that SET ROLE hivemind cannot
replace them, nor read reptracker_app.

The shape server has no network, so there is no DSN for `hive build_schema` to
connect with: each script goes to `$AIDEV_DB_SHAPE_PSQL` (a psql reading SQL on
its standard input, stopping at the first error), one session per script. Left
out, because they change no plan: scripts/setup_postgres.sh and install_app.sh's
role grants (cluster-wide; the shape's roles and memberships are the source's),
the reputation_tracker and HAfAH installs (other applications' code, at the
versions the source runs), and the patch-level and hive_state rows and HAF
application registration setup_runtime_code writes (DATA_ONLY_SCRIPTS and its
Python side).

--list prints the scripts, with the role each runs as, instead of running them.
Exits non-zero naming the script that failed.
"""

import ast
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL_DIR = ROOT / "hive" / "db" / "sql_scripts"
SCHEMA_PY = ROOT / "hive" / "db" / "schema.py"
REPTRACKER_SCHEMA = "reptracker_app"
ADMIN = "admin"
OWNER = "hivemind"
# Scripts that only write rows: a shape's indexes hold their columns' extreme keys,
# so the insert collides with them, and a row changes no plan.
DATA_ONLY_SCRIPTS = {"upgrade/update_db_patchlevel.sql"}


# The source's owner of each schema whose objects hivemind's code replaces or reads
# (`owners`), and of its HAF context's table and sequence in `hive`. A schema's
# owner owns everything in it but the untrusted-language functions (haf_admin's).
OWNERSHIP_SQL = """
DO $$
DECLARE
  _statement TEXT;
BEGIN
  FOR _statement IN
    WITH owners(nspname, owner) AS (
      VALUES ('hivemind_app', 'hivemind'), ('hivemind_endpoints', 'hivemind'), ('hivemind_postgrest_utilities', 'hivemind'),
             ('reptracker_app', 'reptracker_owner'), ('hafah_backend', 'hafah_owner')
    ),
    schemas AS (SELECT n.oid, n.nspname, o.owner FROM pg_namespace n JOIN owners o USING (nspname))
    SELECT format('ALTER SCHEMA %I OWNER TO %I', s.nspname, s.owner) FROM schemas s
    UNION ALL
    SELECT format('ALTER %s %s OWNER TO %I',
                  CASE c.relkind WHEN 'v' THEN 'VIEW' WHEN 'm' THEN 'MATERIALIZED VIEW' WHEN 'S' THEN 'SEQUENCE' ELSE 'TABLE' END,
                  c.oid::regclass, coalesce(s.owner, 'hivemind'))
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace LEFT JOIN schemas s ON s.oid = n.oid
    WHERE (s.oid IS NOT NULL OR (n.nspname = 'hive' AND c.relname IN ('hivemind_app', 'hivemind_app_hive_rowid_seq')))
      AND c.relkind IN ('r', 'p', 'v', 'm', 'S')
      -- a sequence a column owns follows its table
      AND NOT (c.relkind = 'S' AND EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_class'::regclass AND d.objid = c.oid AND d.deptype IN ('a', 'i')))
    UNION ALL
    SELECT format('ALTER ROUTINE %s OWNER TO %I', p.oid::regprocedure, s.owner)
    FROM pg_proc p JOIN schemas s ON s.oid = p.pronamespace JOIN pg_language l ON l.oid = p.prolang
    WHERE l.lanpltrusted
    UNION ALL
    SELECT format('ALTER %s %s OWNER TO %I', CASE t.typtype WHEN 'd' THEN 'DOMAIN' ELSE 'TYPE' END, t.oid::regtype, s.owner)
    FROM pg_type t JOIN schemas s ON s.oid = t.typnamespace
    WHERE t.typtype IN ('d', 'e', 'r') OR (t.typtype = 'c' AND (SELECT relkind FROM pg_class WHERE oid = t.typrelid) = 'c')
  LOOP
    EXECUTE _statement;
  END LOOP;
END
$$;
"""


class ApplyError(Exception):
    pass


def _function(tree: ast.Module, name: str) -> ast.FunctionDef:
    for node in tree.body:
        if isinstance(node, ast.FunctionDef) and node.name == name:
            return node
    raise ApplyError(f"{SCHEMA_PY.relative_to(ROOT)} has no function {name}()")


def _postgrest_scripts() -> list[str]:
    lines = (SQL_DIR / "postgrest" / "load_order.sql").read_text().splitlines()
    includes = (line.strip().removeprefix("\\ir ") for line in lines if line.strip().startswith("\\ir "))
    return [os.path.normpath(f"postgrest/{include.strip()}") for include in includes]


def _script_list(tree: ast.Module, function: str, variable: str) -> list[str]:
    """The literal list `variable` is first assigned in `function`, with `*_postgrest_scripts()` expanded."""
    for node in ast.walk(_function(tree, function)):
        if not (isinstance(node, ast.Assign) and isinstance(node.value, ast.List)):
            continue
        if not any(isinstance(target, ast.Name) and target.id == variable for target in node.targets):
            continue
        scripts: list[str] = []
        for element in node.value.elts:
            if isinstance(element, ast.Constant) and isinstance(element.value, str):
                scripts.append(element.value)
            elif (
                isinstance(element, ast.Starred)
                and isinstance(element.value, ast.Call)
                and isinstance(element.value.func, ast.Name)
                and element.value.func.id == "_postgrest_scripts"
            ):
                scripts.extend(_postgrest_scripts())
            else:
                raise ApplyError(f"{function}() lists a script this reader cannot resolve: {ast.unparse(element)}")
        return scripts
    raise ApplyError(f"{function}() assigns no literal list {variable}")


def _swagger_url() -> str:
    match = re.search(r"^SWAGGER_URL = '(.*)'$", (ROOT / "hive" / "conf.py").read_text(), re.MULTILINE)
    if match is None:
        raise ApplyError("cannot read SWAGGER_URL from hive/conf.py")
    return match.group(1)


def plan() -> list[tuple[str, Path]]:
    """Each script to run, in order, with the role it runs as (ADMIN or OWNER)."""
    tree = ast.parse(SCHEMA_PY.read_text())
    steps = [(ADMIN, ROOT / "scripts" / "install_app.sql")]
    steps += [(ADMIN, SQL_DIR / s) for s in _script_list(tree, "perform_db_upgrade", "sql_scripts")]
    steps += [(ADMIN, SQL_DIR / s) for s in _script_list(tree, "_setup_admin_runtime_code", "admin_sql_scripts")]
    steps += [
        (OWNER, SQL_DIR / s)
        for s in _script_list(tree, "setup_runtime_code", "sql_scripts")
        if s not in DATA_ONLY_SCRIPTS
    ]
    return steps


def _preamble(role: str) -> str:
    lines = ["\\set ON_ERROR_STOP on", f"\\set REPTRACKER_SCHEMA {REPTRACKER_SCHEMA}"]
    if role == OWNER:
        swagger = _swagger_url().replace("'", "''")
        lines += [
            f"SET ROLE {OWNER};",
            f"SET search_path TO {REPTRACKER_SCHEMA};",
            f"SET custom.swagger_url = '{swagger}';",
        ]
    return "\n".join(lines) + "\n"


def _run(psql: list[str], name: str, sql: str) -> None:
    completed = subprocess.run(psql, input=sql, capture_output=True, text=True, check=False)
    if completed.returncode != 0:
        raise ApplyError(
            f"{name} failed (exit {completed.returncode}): {(completed.stderr or completed.stdout).strip()[-1500:]}"
        )


def apply(psql: list[str]) -> None:
    _run(psql, "restoring the source's owners", OWNERSHIP_SQL)
    for role, script in plan():
        name = script.relative_to(ROOT)
        try:
            sql = script.read_text()
        except OSError as exc:
            raise ApplyError(f"{name}: {exc}") from exc
        _run(psql, str(name), _preamble(role) + sql)
        print(f"applied {name} as {role}")


def main(argv: list[str]) -> int:
    try:
        if argv == ["--list"]:
            for role, script in plan():
                print(f"{role}\t{script.relative_to(ROOT)}")
            return 0
        if argv:
            print("usage: shape_apply.py [--list]", file=sys.stderr)
            return 2
        psql = os.environ.get("AIDEV_DB_SHAPE_PSQL")
        if not psql:
            raise ApplyError("AIDEV_DB_SHAPE_PSQL is not set; run this through aidev db shape apply/check")
        apply(shlex.split(psql))
    except ApplyError as exc:
        print(f"shape apply: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
