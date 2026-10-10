#!/usr/bin/env python3
"""Run the tavern API suite against a clone of the shared synced hivemind.

    hivemind_tavern.py OUT_DIR

The provider is the shared hivemind service (`sandbox.external` `hivemind`,
reached at AIDEV_EXTERNAL_HIVEMIND_HOST:AIDEV_EXTERNAL_HIVEMIND_PORT; see
.aidev/README.md). The step:

1. reads this tree's schema revision (update_db_patchlevel.sql) and sync recipe
   (shared_fixture.py, on project.yaml's HAF_FIXTURE_COMMIT) and picks the
   template seeded for both. Without one it asks the provider to seed it
   (request_seed) and takes the newest template of the revision instead, with
   an advisory: its data is schema-compatible but synced by another recipe.
   With no template of the revision it exits SKIP: a missing fixture is the
   host environment's, not the change's;
2. clones the template into run_<id> and reloads this tree's PostgREST SQL into
   it (scripts/ci/reload-postgrest-functions.sh, what CI's POSTGREST_ONLY path
   does), so query changes are tested without a re-sync;
3. serves the clone with PostgREST as scripts/start_postgrest.sh does, and runs
   each tavern group of .gitlab-ci.yml's SMOKETESTS the way
   scripts/ci/start-api-smoketest.sh does (RUN_TESTS_WITH_MARKER as in
   e2e_benchmark_on_postgrest), one junit report per group, OUT_DIR/tavern-<group>.xml;
4. moves the .out.json files tavern writes next to the patterns to
   OUT_DIR/tavern-out/ and drops the clone.

Exits 0 when every group passes, 1 when one fails, SKIP (77) on a revision miss
or a provider whose clone API predates sync recipes;
the last line printed is the reason.
"""

import importlib.util
import os
import re
import shutil
import subprocess
import sys
import time
from types import ModuleType
from typing import Any

from hivemind_smoke import free_port, wait_until_serving

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def _load_shared_fixture() -> ModuleType:
    # The provider's scripts directory is mounted on its own, so the module lives there.
    path = os.path.join(HERE, "shared-hivemind", "shared_fixture.py")
    spec = importlib.util.spec_from_file_location("shared_fixture", path)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


shared_fixture = _load_shared_fixture()

SKIP = 77
TAVERN_DIR = os.path.join(ROOT, "tests", "api_tests", "hivemind", "tavern")
TESTS_API_DIR = os.path.join(ROOT, "tests", "tests_api")
MARKER = "not postgrest_ignore"
# As .gitlab-ci.yml's run-all-smoketests: search-api needs pg_search, which a
# HAF image may lack.
NON_FATAL_GROUPS = {"search-api_patterns"}
_SMOKETESTS_RE = re.compile(r"SMOKETESTS=\((.*?)\)", re.DOTALL)
_SMOKETEST_ENTRY_RE = re.compile(r'"([^":\s]+):[^"\s]+"')


class ProviderError(RuntimeError):
    """The shared hivemind service refused or could not be reached."""


def smoketest_groups(gitlab_ci: str) -> list[str]:
    """The tavern groups .gitlab-ci.yml's run-all-smoketests runs, in its order."""
    block = _SMOKETESTS_RE.search(gitlab_ci)
    if not block:
        raise ValueError("no SMOKETESTS=( … ) list in .gitlab-ci.yml")
    groups = _SMOKETEST_ENTRY_RE.findall(block.group(1))
    if not groups:
        raise ValueError("the SMOKETESTS list in .gitlab-ci.yml names no group")
    return groups


def _psql(url: str, sql: str, **variables: str) -> str:
    args = ["psql", "-X", "-q", "-At", "-v", "ON_ERROR_STOP=1", "-d", url]
    for name, value in variables.items():
        args += ["-v", f"{name}={value}"]
    proc = subprocess.run(args, input=sql, capture_output=True, text=True)
    if proc.returncode != 0:
        raise ProviderError(f"{url.split('@')[-1]}: {proc.stderr.strip()}")
    return proc.stdout.strip()


def _templates(api_url: str) -> list[Any]:
    rows = _psql(api_url, "select revision || ' ' || recipe || ' ' || template from hivemind_shared.health();")
    return [shared_fixture.Template(*line.split(" ", 2)) for line in rows.splitlines() if line]


def _head_commit() -> str | None:
    proc = subprocess.run(["git", "-C", ROOT, "rev-parse", "HEAD"], capture_output=True, text=True)
    commit = proc.stdout.strip()
    return commit if proc.returncode == 0 and re.fullmatch(r"[0-9a-f]{40}", commit) else None


def _request_seed(api_url: str, revision: str, recipe: str) -> bool:
    commit = _head_commit()
    if commit is None:
        return False
    state = _psql(
        api_url,
        "select hivemind_shared.request_seed(:'rev', :'recipe', :'commit');",
        rev=revision,
        recipe=recipe,
        commit=commit,
    )
    print(f"seed request for {commit}: {state}")
    return True


def _reload_sql(run_url: str, log_path: str) -> None:
    # The admin-level script (plpython3u) needs a superuser, which a run is not:
    # it fails with a warning and the template's copy stays.
    with open(log_path, "w") as log:
        proc = subprocess.run(
            [
                os.path.join(ROOT, "scripts", "ci", "reload-postgrest-functions.sh"),
                f"--postgres-url={run_url}",
                f"--admin-url={run_url}",
                "--verify",
            ],
            stdout=log,
            stderr=subprocess.STDOUT,
        )
    if proc.returncode != 0:
        raise ProviderError(f"reloading the tree's SQL into the clone failed (exit {proc.returncode}); see {log_path}")


def _run_group(group: str, port: int, out: str, workers: str) -> int:
    env = dict(
        os.environ,
        HIVEMIND_ADDRESS="127.0.0.1",
        HIVEMIND_PORT=str(port),
        TAVERN_DIR=TAVERN_DIR,
        PYTHONPATH=os.pathsep.join([TESTS_API_DIR, os.path.join(TESTS_API_DIR, "scripts"), ROOT]),
        PYTHONFAULTHANDLER="1",
        PYTHONUNBUFFERED="1",
    )
    args = [
        sys.executable, "-m", "pytest", "-p", "no:cacheprovider",
        "-W", "ignore::pytest.PytestDeprecationWarning",
        "-n", workers, "--dist", "loadfile", "--max-worker-restart", "0",
        "-v", "--tb=short", "-m", MARKER,
        f"--junitxml={os.path.join(out, f'tavern-{group}.xml')}",
        f"{group}/",
    ]  # fmt: skip
    with open(os.path.join(out, f"tavern-{group}.log"), "w") as log:
        return subprocess.run(args, cwd=TAVERN_DIR, env=env, stdout=log, stderr=subprocess.STDOUT).returncode


def _collect_outputs(out: str) -> int:
    moved = 0
    for directory, _, files in os.walk(TAVERN_DIR):
        for name in files:
            if name.endswith(".out.json"):
                source = os.path.join(directory, name)
                target = os.path.join(out, "tavern-out", os.path.relpath(source, TAVERN_DIR))
                os.makedirs(os.path.dirname(target), exist_ok=True)
                shutil.move(source, target)
                moved += 1
    return moved


def _serve_and_test(run_url: str, out: str, groups: list[str]) -> list[str]:
    port = free_port()
    base = f"http://127.0.0.1:{port}"
    log_path = os.path.join(out, "tavern-postgrest.log")
    env = dict(
        os.environ,
        PGRST_DB_URI=run_url,
        PGRST_DB_SCHEMAS="hivemind_endpoints",
        PGRST_DB_ANON_ROLE="hivemind",
        PGRST_DB_POOL="20",
        PGRST_DB_POOL_ACQUISITION_TIMEOUT="10",
        # Tavern posts JSON-RPC to `/`, which the postgrest-rewriter sends to /rpc/home.
        PGRST_DB_ROOT_SPEC="home",
        PGRST_SERVER_HOST="127.0.0.1",
        PGRST_SERVER_PORT=str(port),
    )
    workers = os.environ.get("HIVEMIND_TAVERN_WORKERS", "4")
    failed = []
    with open(log_path, "w") as log:
        proc = subprocess.Popen(["postgrest"], env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            wait_until_serving(base, proc, log_path)
            for group in groups:
                t0 = time.monotonic()
                rc = _run_group(group, port, out, workers)
                verdict = "ok  " if rc == 0 else ("WARN" if group in NON_FATAL_GROUPS else "FAIL")
                print(f"{verdict} {group} ({time.monotonic() - t0:.0f}s, exit {rc})", flush=True)
                if rc != 0 and group not in NON_FATAL_GROUPS:
                    failed.append(group)
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()
    return failed


def main(out: str) -> int:
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(ROOT, shared_fixture.PATCHLEVEL_SQL), encoding="utf-8") as handle:
        revision = shared_fixture.revision(handle.read())
    if revision is None:
        print(f"{shared_fixture.PATCHLEVEL_SQL} names no schema revision")
        return 1
    with open(os.path.join(ROOT, shared_fixture.PROJECT_YAML), encoding="utf-8") as handle:
        haf_commit = shared_fixture.haf_fixture_commit(handle.read())
    if haf_commit is None:
        print(f"{shared_fixture.PROJECT_YAML} names no HAF_FIXTURE_COMMIT")
        return 1
    try:
        recipe = shared_fixture.recipe_of_tree(ROOT, haf_commit)
    except shared_fixture.RecipeError as err:
        print(f"no sync recipe: {err}")
        return 1
    host = os.environ.get("AIDEV_EXTERNAL_HIVEMIND_HOST")
    port = os.environ.get("AIDEV_EXTERNAL_HIVEMIND_PORT")
    if not host or not port:
        print("no shared hivemind service: AIDEV_EXTERNAL_HIVEMIND_HOST/PORT unset (sandbox.external hivemind)")
        return SKIP
    with open(os.path.join(ROOT, ".gitlab-ci.yml"), encoding="utf-8") as handle:
        groups = smoketest_groups(handle.read())

    api_url = f"postgresql://hivemind_shared_consumer@{host}:{port}/hivemind_shared"
    # serve.sh installs admin.sql only when the provider starts.
    if _psql(api_url, "select to_regprocedure('hivemind_shared.request_seed(text, text, text)') is not null;") != "t":
        print("the shared hivemind service's clone API predates sync recipes; it installs this one on its next start")
        return SKIP
    templates = _templates(api_url)
    listed = ", ".join(f"{t.revision}/{t.recipe[:12]}" for t in templates) or "none"
    print(f"schema revision {revision}, sync recipe {recipe}; templates: {listed}")
    template = shared_fixture.select_template(templates, revision, recipe)
    if template is None or template.recipe != recipe:
        requested = _request_seed(api_url, revision, recipe)
        if template is None:
            print(shared_fixture.miss_message(revision, requested=requested))
            return SKIP
        print(shared_fixture.fallback_message(template, recipe, requested=requested))

    run_id = shared_fixture.new_run_id("tavern")
    database = _psql(
        api_url,
        "select hivemind_shared.clone_run_database(:'run', :'rev', :'recipe');",
        run=run_id,
        rev=revision,
        recipe=template.recipe,
    )
    print(f"cloned {template.database} into {database}")
    try:
        run_url = f"postgresql://hivemind@{host}:{port}/{database}"
        _reload_sql(run_url, os.path.join(out, "tavern-reload.log"))
        failed = _serve_and_test(run_url, out, groups)
    finally:
        print(f"moved {_collect_outputs(out)} .out.json files to {os.path.join(out, 'tavern-out')}")
        try:
            _psql(api_url, "select hivemind_shared.drop_run_database(:'run');", run=run_id)
            print(f"dropped {database}")
        except ProviderError as err:
            print(f"dropping {database} failed ({err}); the provider's reaper drops it after its TTL")
    if failed:
        print(f"tavern groups failed: {', '.join(failed)}")
        return 1
    print(f"{len(groups)} tavern groups passed against {template.database}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(f"usage: {sys.argv[0]} OUT_DIR")
    try:
        sys.exit(main(sys.argv[1]))
    except ProviderError as err:
        print(f"shared hivemind service: {err}")
        sys.exit(1)
