#!/usr/bin/env bash
# The step functions are called indirectly, through `step`.
# shellcheck disable=SC2317,SC2329
# The checks AIDEV's verification slots run (.aidev/project.yaml), as one junit
# report per suite: each named step is a test case, its log the failure body.
#
#   .aidev/run-checks.sh <suite> <step>... [--rerun <id>...]
#
#   - unit       pytest on tests/utils, tests/steem and tests/ci, those that exist (the
#                Makefile's test-utils / test-steem); one junit case per test in unit.xml
#   - ruff       `ruff check` and `ruff format --check` on hive/, tests/ and
#                scripts/, with the pyproject.toml configuration
#   - install    into the stack's HAF database (HIVEMIND_TEST_DB_HOST, default `haf`),
#                as the hivemind image's `setup --with-apps` does it:
#                scripts/setup_postgres.sh, the reputation_tracker and HAfAH
#                submodules' install_app.sh, scripts/install_app.sh, then
#                `hive build_schema` from this checkout, then checks hivemind's block
#                processing during an emulated keep-monotonic replay, in a transaction
#                rolled back: .aidev/early_block_processing_check.sql; and that the
#                hivemind role holds no TRUNCATE, REFERENCES or TRIGGER on HAF's control
#                tables: .aidev/haf_control_table_privileges_check.sql; and that it is
#                registered in HAF's application registry as 'hivemind', refuses a row of its
#                context under the old name 'hivemind_app' and keeps a paused registration
#                over a re-install: .aidev/app_registry_check.sql
#   - reinstall  scripts/uninstall_app.sh, then the hivemind half of install again
#   - mock-wrapper  scripts/ci/wrapper_for_app_next_block.sql applied twice to the
#                stack's HAF and checked, in a transaction rolled back:
#                .aidev/app_next_block_wrapper_check.sql
#   - api-smoke  PostgREST over the installed schema, JSON-RPC calls checked by
#                .aidev/hivemind_smoke.py; one junit case per call
#   - tavern     CI's tavern API suite against a clone of the shared synced hivemind
#                (sandbox.external hivemind), with this tree's PostgREST SQL reloaded
#                into it: .aidev/hivemind_tavern.py; one junit report per group
#
# install, reinstall, mock-wrapper and api-smoke need the HAF stack (.aidev/test-stack.compose.yml),
# tavern the shared hivemind service. A step exiting 77 is skipped, not failed: its
# precondition is the host environment's (tavern: no fixture for this tree's schema
# revision yet); the last line it printed is the reason.
# Reports go to test-results/<suite>/: junit.xml (one case per step) plus
# unit.xml, api-smoke.xml and tavern-<group>.xml, one case per test. A step that
# exits 1 with failures recorded there is reported skipped in junit.xml, pointing
# at them (.aidev/junit_cases.py), so each failure is reported once, under the
# test's own id, where .aidev/known_failures.txt or a re-run can name it. Exit 1 is
# how unit, api-smoke and tavern say their failures are recorded per test; a step
# failing any other way (a crash, a group that wrote no report) fails as itself.
#
# --rerun runs only the named tests, through the listed steps that own them, and
# reports to test-results/<suite>/rerun/<n>/, leaving the run it re-runs intact.
# That is under the slot's declared artifacts path, so aidev's causality check
# reads a re-run on the base tree as a verdict: an id its report does not name is
# absent on base. aidev reads and keeps a run's own reports before re-running any
# of its failures, so a re-run's report never joins them; the next run's rm -rf
# removes it. Each argument is a test id as the junit reports name it, or a file:
#   - `<path>.py[::<test>]` under one of UNIT_DIRS: unit, the node id as given;
#   - `api-smoke::<call>`: api-smoke, only those calls (`hivemind_smoke.py --list`);
#   - anything else: tavern, as .aidev/hivemind_tavern.py's selectors — a tavern id
#     (`<dotted.path>.tavern.yaml::<title>`, which re-runs its whole file), a tavern
#     file, or a rest_api_* test (`<group>/<module>.py::<test>`).
# unit runs from the checkout and tavern on its own clone; api-smoke's calls need
# the schema, so install runs first when it is listed. The exit status is 0 only
# when every named test ran and passed: an argument no listed step owns, or an
# owning step that skips, fails the re-run, since a test that never ran must not
# read as passing. An id naming no test of this tree (a unit node id pytest does
# not collect, an api-smoke call hivemind_smoke.py does not make, a tavern selector
# no group holds) is a verdict, not here: the re-run fails with a case for it that
# does not name it, so aidev reads the id as absent. An owning step exiting other
# than 0 or 1 (a skip, a crash, a setup or collection error), or api-smoke's
# install failing, reached no verdict, and a report naming other tests would read
# as one, the named id absent: the re-run then keeps that step's reports and
# junit.xml as <name>.xml.no-verdict, so with no report of its own aidev reads the
# id as failing, not as absent.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
root="$PWD"

suite="${1:?usage: $0 <suite> <step>... [--rerun <id>...]}"; shift
steps=()
while [ $# -gt 0 ] && [ "$1" != --rerun ]; do steps+=("$1"); shift; done
rerun=()
if [ $# -gt 0 ]; then
    shift
    rerun=("$@")
    [ ${#rerun[@]} -gt 0 ] || { echo "--rerun needs at least one test id" >&2; exit 2; }
fi
for s in "${steps[@]}"; do
    case "$s" in
        unit|ruff|install|reinstall|mock-wrapper|api-smoke|tavern) ;;
        *) echo "unknown step: $s" >&2; exit 2 ;;
    esac
done
for s in "${rerun[@]}"; do
    # The arguments reach the test runners' argv: none may pass as an option.
    [[ "$s" != -* ]] || { echo "--rerun: not a test id: $s" >&2; exit 2; }
done

if [ ${#rerun[@]} -eq 0 ]; then
    out="$root/test-results/$suite"
    rm -rf "$out"; mkdir -p "$out"
else
    mkdir -p "$root/test-results/$suite/rerun"
    n=1
    until mkdir "$root/test-results/$suite/rerun/$n" 2>/dev/null; do n=$((n + 1)); done
    out="$root/test-results/$suite/rerun/$n"
fi
cases="$out/cases.tsv"; : > "$cases"

DB_HOST="${HIVEMIND_TEST_DB_HOST:-haf}"
ADMIN_URL="postgresql://haf_admin@$DB_HOST/haf_block_log"
export HIVEMIND_TEST_USER_URL="postgresql://hivemind@$DB_HOST/haf_block_log"
REPTRACKER_SCHEMA=reptracker_app

status=0
no_verdict=()
no_verdict_reports=()
SKIP_RC=77
# record CASES_FILE NAME RC SECONDS LOG [TESTS_JUNIT]
record() {
    if [ "$3" -eq 0 ]; then
        printf 'case\t%s\tpass\t%s\t\n' "$2" "$4" >> "$1"
    elif [ "$3" -eq "$SKIP_RC" ]; then
        printf 'case\t%s\tskip\t%s\t%s\n' "$2" "$4" "$(grep -v '^[[:space:]]*$' "$5" | tail -1 | tr '\t' ' ')" >> "$1"
    else
        printf 'case\t%s\tfail\t%s\texit %s\t%s\t%s\n' "$2" "$4" "$3" "$5" "${6:-}" >> "$1"
    fi
}

step() {  # NAME TESTS_JUNIT COMMAND...  (TESTS_JUNIT: the per-test junit it writes, a path or glob, or "")
    local name="$1" tests_junit="$2"; shift 2
    local log="$out/$name.log" t0=$SECONDS rc=0
    echo "== $name" >&2
    "$@" > "$log" 2>&1 < /dev/null || rc=$?
    if [ "$rc" -eq "$SKIP_RC" ]; then
        echo "skipped: $(grep -v '^[[:space:]]*$' "$log" | tail -1)" >&2
        [ ${#rerun[@]} -eq 0 ] || status=1
    elif [ "$rc" -ne 0 ]; then
        status=1; tail -40 "$log" >&2
    fi
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
        no_verdict+=("$name")
        [ -z "$tests_junit" ] || no_verdict_reports+=("${tests_junit#"$out/"}")
    fi
    [ "$rc" -eq 1 ] || tests_junit=""
    record "$cases" "$name" "$rc" "$((SECONDS - t0))" "$log" "$tests_junit"
    return "$rc"
}

# hive/_version.py is generated by versioningit at `pip install` time and gitignored;
# `hive` runs from this checkout here, so write it when the checkout has none.
ensure_version() {
    [ -f hive/_version.py ] && return 0
    local rev
    rev="$(git rev-parse HEAD 2>/dev/null || echo aidev)"
    printf "__version__ = '0.0.0+aidev'\n__git_revision__ = '%s'\n__git_revision_date__ = '%s'\n" \
        "$rev" "$(date -u +%Y-%m-%dT%H:%M:%S)" > hive/_version.py
}

# The tests write scratch files (e.g. .tmp.test-prof) relative to the working
# directory: run them from a scratch one so the checkout stays clean. A directory
# of UNIT_DIRS that doesn't exist is skipped, so removing one doesn't break the step.
UNIT_DIRS=(tests/utils tests/steem tests/ci)
unit() {  # [NODE_ID...]  (repository-relative; default: every test under UNIT_DIRS)
    ensure_version
    local scratch dir id rc=0
    local -a targets=()
    if [ $# -gt 0 ]; then
        for id in "$@"; do targets+=("$root/$id"); done
    else
        for dir in "${UNIT_DIRS[@]}"; do
            [ -d "$dir" ] && targets+=("$root/$dir")
        done
        [ "${#targets[@]}" -gt 0 ] || { echo "none of ${UNIT_DIRS[*]} exists"; return 1; }
    fi
    scratch="$(mktemp -d)"
    (cd "$scratch" && PYTHONPATH="$root" python3 -m pytest -p no:cacheprovider --rootdir="$root" \
        --junitxml="$out/unit.xml" -o junit_suite_name=unit "${targets[@]}") || rc=$?
    rm -rf "$scratch"
    return "$rc"
}

run_ruff() {
    ruff --version
    local rc=0
    ruff check --no-cache hive tests scripts || rc=1
    ruff format --no-cache --check hive tests scripts || rc=1
    return "$rc"
}

# The install scripts write their logs next to themselves and the submodules'
# version files come from git, which a workflow checkout may not have: stage them
# in a scratch directory and write the version files there.
stage=""
stage_sources() {
    [ -n "$stage" ] && return 0
    stage="$(mktemp -d)"
    cp -r scripts reputation_tracker hafah "$stage/"
    local rt ha
    rt="$(git -C reputation_tracker rev-parse HEAD 2>/dev/null || echo aidev)"
    ha="$(git -C hafah rev-parse HEAD 2>/dev/null || echo aidev)"
    printf "TRUNCATE TABLE version; INSERT INTO version(git_hash) VALUES ('%s');\n" \
        "$rt" > "$stage/reputation_tracker/scripts/set_version_in_sql.pgsql"
    printf "TRUNCATE TABLE hafah_backend.version; INSERT INTO hafah_backend.version(git_hash) VALUES ('%s');\n" \
        "$ha" > "$stage/hafah/scripts/set_version_in_sql.pgsql"
}

wait_for_db() {
    local i
    for i in $(seq 60); do
        psql "$ADMIN_URL" -Atc "select 1" >/dev/null 2>&1 && break
        echo "waiting for $ADMIN_URL ($i)"
        sleep 5
    done
    # This database has never seen hived. hived calls hive.initialize_extension_data()
    # when it first connects; it fills hafd.events_queue and hafd.hive_state. Without
    # events_queue, hive.is_instance_ready() is false and hivemind's API refuses
    # ("HAF instance is not ready", e.g. get_sync_status). (A HAF older than
    # hive/haf#354 also needed hive_state, or app_register_table skipped hive_rowid.)
    # Stand in for hived connecting.
    psql "$ADMIN_URL" -v ON_ERROR_STOP=on -Atc "select hive.initialize_extension_data()"
}

install_hivemind() {
    (cd "$stage" && bash scripts/setup_postgres.sh --postgres-url="$ADMIN_URL") || return 1
    (cd "$stage" && bash scripts/install_app.sh --postgres-url="$ADMIN_URL" \
        --reptracker-schema-name="$REPTRACKER_SCHEMA") || return 1
    ensure_version
    build_schema || return 1
    psql "$ADMIN_URL" -v ON_ERROR_STOP=on -Atc \
        "select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'hivemind_endpoints'" \
        | awk '{ print "hivemind_endpoints functions: " $1; exit ($1 > 0 ? 0 : 1) }' || return 1
    check_control_table_privileges || return 1
    check_app_registry || return 1
    if [ "$(psql "$ADMIN_URL" -Atc "select to_regprocedure('hive.app_context_set_early_block_processing(hive.contexts_group, boolean)') is null")" = t ]; then
        echo "early block processing check skipped: this HAF predates hive/haf#379"
        return 0
    fi
    psql "$ADMIN_URL" -X -v ON_ERROR_STOP=1 -f .aidev/early_block_processing_check.sql
}

# hive/haf#348 added no function to probe for; what it changed is HAF's own grant, so
# the probe is that grant: a HAF still giving hive_applications_group TRUNCATE on
# hafd.contexts predates it.
check_control_table_privileges() {
    local before
    before="$(psql "$ADMIN_URL" -X -v ON_ERROR_STOP=on -Atc \
        "select has_table_privilege('hive_applications_group', 'hafd.contexts', 'TRUNCATE')")" || return 1
    if [ "$before" = t ]; then
        echo "HAF control table privilege check skipped: this HAF predates hive/haf#348" \
            "(hive_applications_group holds TRUNCATE on hafd.contexts)"
        return 0
    fi
    psql "$ADMIN_URL" -X -v ON_ERROR_STOP=1 -f .aidev/haf_control_table_privileges_check.sql
}

build_schema() {
    PYTHONPATH="$root" python3 -m hive.cli build_schema --database-url="$ADMIN_URL"
}

registry_row() {  # NAME: the row's contexts, owner and paused flag, or nothing
    psql "$ADMIN_URL" -X -v ON_ERROR_STOP=on -Atc \
        "select contexts::text || ' ' || owner || ' ' || paused from hafd.applications where name = '$1'"
}

# hivemind registers under its lock name 'hivemind'; an install refuses a row of its
# context under another name (an older hivemind's 'hivemind_app') and leaves it, and a
# re-install over its own row keeps the row's paused flag.
check_app_registry() {
    if [ "$(psql "$ADMIN_URL" -Atc "select to_regprocedure('hive.app_register(text, hive.contexts_group, text, text)') is null")" = t ]; then
        echo "HAF application registry check skipped: this HAF predates hive/haf#341"
        return 0
    fi
    psql "$ADMIN_URL" -X -v ON_ERROR_STOP=1 -f .aidev/app_registry_check.sql || return 1

    psql "$ADMIN_URL" -X -v ON_ERROR_STOP=on -Atc "select hive.app_pause('hivemind')" || return 1
    build_schema || { echo "re-install over the hivemind registration failed"; return 1; }
    [ "$(psql "$ADMIN_URL" -Atc "select paused from hafd.applications where name = 'hivemind'")" = t ] \
        || { echo "re-install did not keep the hivemind registration paused"; return 1; }
    psql "$ADMIN_URL" -X -v ON_ERROR_STOP=on -Atc "select hive.app_resume('hivemind')" || return 1
    echo "re-install over the hivemind registration kept it paused"

    psql "$ADMIN_URL" -X -v ON_ERROR_STOP=on -Atc "select hive.app_unregister('hivemind'); \
        select hive.app_register('hivemind_app', ARRAY['hivemind_app']::hive.contexts_group, NULL, 'hivemind_app.completed_block_num')" || return 1
    local planted refused
    planted="$(registry_row hivemind_app)" || return 1
    refused="$(mktemp)"
    if build_schema > "$refused" 2>&1; then
        cat "$refused"; echo "install over a hivemind_app registration did not fail"; return 1
    fi
    grep -F "registered in the HAF application registry as 'hivemind_app'" "$refused" \
        && grep -qF "SELECT hive.app_unregister('hivemind_app');" "$refused" \
        || { cat "$refused"; echo "install over a hivemind_app registration failed without naming the row"; return 1; }
    [ "$(registry_row hivemind_app)" = "$planted" ] && [ -z "$(registry_row hivemind)" ] \
        || { echo "the refused install changed the registry: hivemind_app $(registry_row hivemind_app), hivemind $(registry_row hivemind)"; return 1; }
    echo "install over a hivemind_app registration refused, row left as $planted"

    psql "$ADMIN_URL" -X -v ON_ERROR_STOP=on -Atc "select hive.app_unregister('hivemind_app')" || return 1
    build_schema || return 1
    psql "$ADMIN_URL" -X -v ON_ERROR_STOP=1 -f .aidev/app_registry_check.sql
}

install() {
    stage_sources && wait_for_db || return 1
    (cd "$stage/reputation_tracker" && bash scripts/install_app.sh --postgres-url="$ADMIN_URL" \
        --schema="$REPTRACKER_SCHEMA" --is_forking=false) || return 1
    (cd "$stage/hafah" && bash scripts/install_app.sh --postgres-url="$ADMIN_URL") || return 1
    install_hivemind
}

reinstall() {
    stage_sources && wait_for_db || return 1
    (cd "$stage" && bash scripts/uninstall_app.sh --postgres-url="$ADMIN_URL") || return 1
    install_hivemind
}

mock_wrapper() {
    wait_for_db || return 1
    psql "$ADMIN_URL" -X -v ON_ERROR_STOP=1 -f .aidev/app_next_block_wrapper_check.sql
}

# Whether NODE_ID may name a test of this tree: pytest exiting 4 (not found) or 5
# (no tests collected) on it says it names none, unless a module failed to
# collect; that, like any other failure, is left for the run to report as itself.
unit_names_a_test() {  # NODE_ID
    local scratch log rc=0
    [ -e "$root/${1%%::*}" ] || return 1
    ensure_version
    scratch="$(mktemp -d)"
    log="$scratch.log"
    (cd "$scratch" && PYTHONPATH="$root" python3 -m pytest -p no:cacheprovider --rootdir="$root" \
        --collect-only -q "$root/$1") > "$log" 2>&1 < /dev/null || rc=$?
    cat "$log" >> "$out/unit-collect.log"
    rm -rf "$scratch"
    if { [ "$rc" -eq 4 ] || [ "$rc" -eq 5 ]; } && ! grep -q ' ERROR collecting ' "$log"; then
        rm -f "$log"; return 1
    fi
    rm -f "$log"
}

# Whether the call an `api-smoke::<call>` id names is one hivemind_smoke.py makes.
SMOKE_PREFIX="api-smoke::"
smoke_calls_listed=""
smoke_names_a_call() {  # ID
    if [ -z "$smoke_calls_listed" ]; then
        smoke_calls_listed="$(python3 .aidev/hivemind_smoke.py --list)" ||
            { echo "hivemind_smoke.py --list failed" >&2; exit 2; }
    fi
    grep -qxF -- "${1#"$SMOKE_PREFIX"}" <<< "$smoke_calls_listed"
}

rerun_owner() {  # ARG: the step that runs the test it names
    local file="${1%%::*}" dir
    [[ "$1" == "$SMOKE_PREFIX"* ]] && { echo api-smoke; return; }
    if [[ "$file" == *.py ]]; then
        for dir in "${UNIT_DIRS[@]}"; do
            [[ "$file" == "$dir"/* ]] && { echo unit; return; }
        done
    fi
    echo tavern
}

if [ ${#rerun[@]} -eq 0 ]; then
    for s in "${steps[@]}"; do
        case "$s" in
            unit) step unit "$out/unit.xml" unit ;;
            ruff) step ruff "" run_ruff ;;
            install) step install "" install ;;
            reinstall) step reinstall "" reinstall ;;
            mock-wrapper) step mock-wrapper "" mock_wrapper ;;
            api-smoke) step api-smoke "$out/api-smoke.xml" python3 .aidev/hivemind_smoke.py "$out" ;;
            tavern) step tavern "$out/tavern-*.xml" python3 .aidev/hivemind_tavern.py "$out" ;;
        esac
    done
else
    unit_ids=(); smoke_calls=(); tavern_ids=(); unowned=(); absent=()
    for arg in "${rerun[@]}"; do
        owner="$(rerun_owner "$arg")"
        if [[ " ${steps[*]} " != *" $owner "* ]]; then
            unowned+=("$arg")
        elif [ "$owner" = unit ]; then
            if unit_names_a_test "$arg"; then unit_ids+=("$arg"); else absent+=("$arg"); fi
        elif [ "$owner" = api-smoke ]; then
            if smoke_names_a_call "$arg"; then smoke_calls+=("${arg#"$SMOKE_PREFIX"}"); else absent+=("$arg"); fi
        else
            tavern_ids+=("$arg")
        fi
    done
    [ ${#unit_ids[@]} -eq 0 ] || step unit "$out/unit.xml" unit "${unit_ids[@]}"
    if [ ${#smoke_calls[@]} -gt 0 ]; then
        if [[ " ${steps[*]} " != *" install "* ]] || step install "" install; then
            step api-smoke "$out/api-smoke.xml" python3 .aidev/hivemind_smoke.py "$out" "${smoke_calls[@]}"
        elif [[ " ${no_verdict[*]} " != *" install "* ]]; then
            # The calls never ran: a report naming only install would read as them being absent.
            no_verdict+=(install)
        fi
    fi
    [ ${#tavern_ids[@]} -eq 0 ] ||
        step tavern "$out/tavern-*.xml" python3 .aidev/hivemind_tavern.py "$out" "${tavern_ids[@]}"
    if [ ${#unowned[@]} -gt 0 ]; then
        status=1
        echo "re-run ids no listed step (${steps[*]}) runs: ${unowned[*]}" >&2
        printf 'case\trerun-ids\tfail\t0\tre-run ids no listed step runs: %s\n' "${unowned[*]}" >> "$cases"
    fi
    if [ ${#absent[@]} -gt 0 ]; then
        status=1
        echo "re-run ids naming no test of this tree: ${absent[*]}" >&2
        printf 'case\trerun-absent\tfail\t0\tre-run ids naming no test of this tree: %s\n' "${absent[*]}" >> "$cases"
    fi
fi
[ -n "$stage" ] && rm -rf "$stage"
if [ ${#rerun[@]} -gt 0 ] && [ ${#no_verdict[@]} -gt 0 ]; then
    echo "re-run reached no verdict in: ${no_verdict[*]}; their reports are kept as *.xml.no-verdict" >&2
    for pattern in "${no_verdict_reports[@]}"; do
        # A report name under $out, or a glob of them: expand it.
        # shellcheck disable=SC2086
        for report in "$out"/$pattern; do
            [ -f "$report" ] && mv "$report" "$report.no-verdict"
        done
    done
    python3 .aidev/junit_cases.py "$out/junit.xml.no-verdict" "$suite" "$cases"
else
    python3 .aidev/junit_cases.py "$out/junit.xml" "$suite" "$cases"
fi
exit "$status"
