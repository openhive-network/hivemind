#!/usr/bin/env python3
"""Run the finalization equality test on a clone of the shared synced hivemind of its own.

    hivemind_finalization.py OUT_DIR [SELECTOR...]

tests/finalization/test_finalization_equality.py runs the post-sync finalization
serially and in parallel on the database HIVEMIND_FINALIZATION_DB_URL names and
compares the data, rewriting hive_votes, hive_posts and the caches as it goes. So
it gets a clone nobody else reads: the step takes one of the template the tavern
step would take (hivemind_tavern.clone_fixture: the tree's schema revision and
sync recipe, a seed request on a miss), runs the test there, writing
OUT_DIR/finalization.xml and pytest's output, its --durations table last, to
OUT_DIR/finalization-tests.log, and drops the clone, also
when the run fails. The PostgREST SQL is not reloaded: the test reads none of it,
and loads the finalization SQL it tests from this tree itself.

With SELECTORs only the tests they name run (a re-run, .aidev/run-checks.sh
--rerun): each is a node id `tests/finalization/<module>.py[::<test>]`, run as
given. A selector naming no file under tests/finalization names no test of this
tree: that is a verdict, reached before the provider is asked for anything, so
it is recorded as the failing case `rerun-ids` of
OUT_DIR/finalization-rerun-ids.xml, which does not name it, and fails the run
(exit 1).

Exits as hivemind_tavern.py does: 0 when the tests pass; 1 only when pytest ran
the tests (exit 1), finalization.xml records each failure and every selector
naming no test is recorded; 2 for any other failure (a crash, a collection error,
the provider refusing); SKIP (77) when there is no fixture for the tree's schema
revision or no provider. The last line printed is the reason.
"""

import os
import subprocess
import sys
import time
import traceback

import hivemind_tavern
from junit_cases import recorded_failures

STEP = "finalization"
TESTS = os.path.join("tests", "finalization")


def resolve_selectors(selectors: list[str]) -> tuple[list[str], list[str]]:
    """The node ids of `selectors` naming a file under tests/finalization, and the selectors naming none."""
    targets = [
        selector
        for selector in selectors
        if selector.startswith(TESTS + os.sep)
        and selector.partition("::")[0].endswith(".py")
        and os.path.isfile(os.path.join(hivemind_tavern.ROOT, selector.partition("::")[0]))
    ]
    return targets, [selector for selector in selectors if selector not in targets]


def _run_tests(run_url: str, targets: list[str], out: str) -> int:
    """pytest's exit status for `targets` run on the clone `run_url`."""
    env = dict(
        os.environ,
        HIVEMIND_FINALIZATION_DB_URL=run_url,
        PYTHONPATH=hivemind_tavern.ROOT,
        PYTHONFAULTHANDLER="1",
        PYTHONUNBUFFERED="1",
    )
    args = [
        sys.executable, "-m", "pytest", "-p", "no:cacheprovider", "--rootdir", hivemind_tavern.ROOT,
        "-v", "--tb=short", "--log-level=INFO", "--durations=0",
        f"--junitxml={os.path.join(out, f'{STEP}.xml')}",
        *targets,
    ]  # fmt: skip
    t0 = time.monotonic()
    # OUT_DIR/finalization.log is run-checks.sh's log of the step itself.
    with open(os.path.join(out, f"{STEP}-tests.log"), "w") as log:
        rc = subprocess.run(args, cwd=hivemind_tavern.ROOT, env=env, stdout=log, stderr=subprocess.STDOUT).returncode
    print(f"{'ok  ' if rc == 0 else 'FAIL'} {STEP} ({time.monotonic() - t0:.0f}s, exit {rc})", flush=True)
    return rc


def run_status(out: str, rc: int, unresolved: list[str]) -> int:
    """The step's exit status for pytest's `rc` (the module docstring's 0, 1 or 2), printing why."""
    if rc != 0 and (rc != hivemind_tavern.TESTS_FAILED or not recorded_failures(os.path.join(out, f"{STEP}.xml"))):
        print(f"the finalization equality test failed without running its tests and recording each failure (exit {rc})")
        return hivemind_tavern.UNREPORTED
    if rc != 0 or unresolved:
        return hivemind_tavern.TESTS_FAILED
    return 0


def main(out: str, selectors: list[str]) -> int:
    os.makedirs(out, exist_ok=True)
    if selectors:
        targets, unresolved = resolve_selectors(selectors)
        if unresolved:
            print(f"selectors naming no test of {TESTS}: {' '.join(unresolved)}")
            hivemind_tavern.write_unresolved_report(out, unresolved, STEP, TESTS)
        if not targets:
            return hivemind_tavern.TESTS_FAILED
    else:
        targets, unresolved = [TESTS], []
    clone = hivemind_tavern.clone_fixture(STEP)
    if isinstance(clone, int):
        return clone
    try:
        rc = _run_tests(clone.url, targets, out)
    finally:
        hivemind_tavern.drop_clone(clone)
    status = run_status(out, rc, unresolved)
    if status == 0:
        print(f"the finalization equality test passed against {clone.template.database}")
    return status


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(f"usage: {sys.argv[0]} OUT_DIR [SELECTOR...]")
    try:
        sys.exit(main(sys.argv[1], sys.argv[2:]))
    except hivemind_tavern.ProviderError as err:
        print(f"shared hivemind service: {err}")
        sys.exit(hivemind_tavern.UNREPORTED)
    except Exception:
        traceback.print_exc(file=sys.stdout)
        print("finalization step crashed; see the traceback above")
        sys.exit(hivemind_tavern.UNREPORTED)
