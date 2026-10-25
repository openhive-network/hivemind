#!/bin/bash
#
# reload-postgrest-functions.sh
#
# Reloads PostgREST SQL functions on an existing hivemind database.
# Used in CI when only PostgREST/SQL endpoint code changes (not the indexer).
#
# This allows skipping the full sync and reusing cached data when only
# API function code changed.
#
# IMPORTANT: The SQL file list is read from hive/db/sql_scripts/postgrest/load_order.sql,
# the same manifest hive/db/schema.py installs from.
#
# Usage:
#   ./scripts/ci/reload-postgrest-functions.sh --postgres-url=postgresql://hivemind@localhost:5432/haf_block_log
#
# Options:
#   --postgres-url=URL    PostgreSQL connection URL (required)
#   --admin-url=URL       Admin PostgreSQL URL for plpython3u scripts (optional, defaults to haf_admin)
#   --skip-admin-scripts  Do not load the plpython3u scripts (the caller installs them as a superuser)
#   --verify              Verify functions exist after reload
#   --postgrest-url=URL   PostgREST server already serving this database: wait until its schema
#                         cache shows the reloaded functions, failing after --postgrest-timeout
#   --postgrest-timeout=S Seconds to wait for that (default 120)
#   --help                Show this help message
#

set -euo pipefail

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
REPO_ROOT="$(cd "$SCRIPTPATH/../.." && pwd)"

print_help() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Reloads PostgREST SQL functions on an existing hivemind database."
    echo
    echo "OPTIONS:"
    echo "  --postgres-url=URL    PostgreSQL connection URL (required)"
    echo "  --admin-url=URL       Admin PostgreSQL URL (optional)"
    echo "  --skip-admin-scripts  Do not load the plpython3u scripts"
    echo "  --verify              Verify functions exist after reload"
    echo "  --postgrest-url=URL   Wait until the PostgREST server at URL serves the reloaded functions"
    echo "  --postgrest-timeout=S Seconds to wait for that (default 120)"
    echo "  --help                Show this help message"
    echo
}

POSTGRES_URL=""
ADMIN_URL=""
SKIP_ADMIN_SCRIPTS=false
VERIFY=false
POSTGREST_URL=""
POSTGREST_TIMEOUT=120

while [ $# -gt 0 ]; do
    case "$1" in
        --postgres-url=*)
            POSTGRES_URL="${1#*=}"
            ;;
        --admin-url=*)
            ADMIN_URL="${1#*=}"
            ;;
        --skip-admin-scripts)
            SKIP_ADMIN_SCRIPTS=true
            ;;
        --verify)
            VERIFY=true
            ;;
        --postgrest-url=*)
            POSTGREST_URL="${1#*=}"
            ;;
        --postgrest-timeout=*)
            POSTGREST_TIMEOUT="${1#*=}"
            ;;
        --help)
            print_help
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1"
            print_help
            exit 1
            ;;
    esac
    shift
done

if [ -z "$POSTGRES_URL" ]; then
    echo "ERROR: --postgres-url is required"
    print_help
    exit 1
fi

# Extract admin URL if not provided
if [ -z "$ADMIN_URL" ]; then
    ADMIN_URL=$(echo "$POSTGRES_URL" | sed 's|://[^@]*@|://haf_admin@|')
fi

SQL_SCRIPTS_DIR="$REPO_ROOT/hive/db/sql_scripts"
LOAD_ORDER="$SQL_SCRIPTS_DIR/postgrest/load_order.sql"

# endpoints/endpoint_schema.sql reads custom.swagger_url; set it to the value
# hive/db/db_state.py sets before installing the runtime code.
SWAGGER_URL=$(sed -n "s/^SWAGGER_URL = '\(.*\)'$/\1/p" "$REPO_ROOT/hive/conf.py")
if [ -z "$SWAGGER_URL" ]; then
    echo "ERROR: cannot read SWAGGER_URL from hive/conf.py"
    exit 1
fi
SET_SWAGGER_URL="SET custom.swagger_url = '${SWAGGER_URL//\'/\'\'}'"

echo "=== Reloading PostgREST SQL functions ==="
echo "PostgreSQL URL: ${POSTGRES_URL%%@*}@..."
echo "SQL scripts dir: $SQL_SCRIPTS_DIR"

# List the PostgREST/endpoint scripts the manifest includes (`\ir <path>`, relative
# to postgrest/), as paths relative to $SQL_SCRIPTS_DIR
extract_postgrest_scripts() {
    sed -n 's|^[[:space:]]*\\ir[[:space:]]\{1,\}\([^[:space:]]*\).*|postgrest/\1|p' "$LOAD_ORDER" | \
        sed 's|^postgrest/\.\./||'
}

# Function to load a SQL script
load_sql() {
    local url="$1"
    local script="$2"
    local script_path="$SQL_SCRIPTS_DIR/$script"

    if [ ! -f "$script_path" ]; then
        echo "ERROR: Script not found: $script"
        exit 1
    fi
    echo "  Loading: $script"
    if ! psql "$url" -v ON_ERROR_STOP=on -c "$SET_SWAGGER_URL" -f "$script_path"; then
        echo "ERROR: Failed to load $script"
        exit 1
    fi
}

# First, execute admin-level scripts (plpython3u)
# These are defined in setup_db() in schema.py
if [ "$SKIP_ADMIN_SCRIPTS" = false ]; then
    echo ""
    echo "=== Installing admin-level scripts ==="
    load_sql "$ADMIN_URL" "postgrest/utilities/preprocess_search_query.sql"
fi

# Load PostgREST scripts in manifest order
# This ensures proper dependency resolution
echo ""
echo "=== Loading PostgREST scripts (from postgrest/load_order.sql) ==="

# Extract and load scripts
SCRIPT_COUNT=0
while IFS= read -r script; do
    load_sql "$POSTGRES_URL" "$script"
    SCRIPT_COUNT=$((SCRIPT_COUNT + 1))
done < <(extract_postgrest_scripts)

echo ""
echo "Loaded $SCRIPT_COUNT PostgREST/endpoint scripts"

# Verification step
if [ "$VERIFY" = true ]; then
    echo ""
    echo "=== Verifying PostgREST functions ==="

    # Check key functions exist in hivemind_endpoints schema
    VERIFICATION_QUERY=$(cat <<'EOF'
SELECT routine_schema, routine_name
FROM information_schema.routines
WHERE routine_schema IN ('hivemind_endpoints', 'hivemind_postgrest_utilities')
ORDER BY routine_schema, routine_name
LIMIT 20;
EOF
)
    echo "Sample PostgREST functions:"
    psql "$POSTGRES_URL" -c "$VERIFICATION_QUERY"

    # Check function count
    COUNT_QUERY=$(cat <<'EOF'
SELECT
    routine_schema,
    COUNT(*) as function_count
FROM information_schema.routines
WHERE routine_schema IN ('hivemind_endpoints', 'hivemind_postgrest_utilities')
GROUP BY routine_schema;
EOF
)
    echo ""
    echo "Function counts by schema:"
    psql "$POSTGRES_URL" -c "$COUNT_QUERY"

    # Verify the ranked-posts overlay functions survived the CASCADE type drops in operation.sql (issue #326)
    echo ""
    echo "=== Verifying ranked posts overlay functions ==="
    OVERLAY_FUNCTIONS="'valid_ranked_posts_overlay_request', 'get_ranked_posts_overlay', 'get_ranked_posts_overlay_internal', 'get_reblogs', 'get_votes'"
    psql "$POSTGRES_URL" -c "SELECT routine_schema, routine_name FROM information_schema.routines WHERE routine_name IN ($OVERLAY_FUNCTIONS) ORDER BY routine_schema, routine_name;"

    OVERLAY_COUNT=$(psql "$POSTGRES_URL" -t -c "SELECT COUNT(DISTINCT routine_name) FROM information_schema.routines WHERE routine_name IN ($OVERLAY_FUNCTIONS)")
    OVERLAY_COUNT=$(echo "$OVERLAY_COUNT" | tr -d ' ')
    if [ "$OVERLAY_COUNT" -lt 5 ]; then
        echo "ERROR: Expected 5 ranked posts overlay functions, found $OVERLAY_COUNT"
        echo "The CASCADE DROP in operation.sql likely destroyed them"
        exit 1
    else
        echo "OK: Found $OVERLAY_COUNT ranked posts overlay functions"
    fi
fi

# PostgREST builds its schema cache at startup, so a running server keeps the old
# function signatures until told to rebuild it (db-channel, default `pgrst`).
notify_postgrest() {
    if ! psql "$POSTGRES_URL" -v ON_ERROR_STOP=on -c "NOTIFY pgrst, 'reload schema'"; then
        echo "ERROR: Failed to notify PostgREST to reload its schema cache"
        exit 1
    fi
}

echo ""
echo "=== Refreshing the PostgREST schema cache ==="
if [ -z "$POSTGREST_URL" ]; then
    notify_postgrest
else
    # The cache is rebuilt from one catalog snapshot, so once a function created after
    # the reload is served, every reloaded function is too.
    PROBE="hivemind_endpoints.reload_probe_$$_$(date +%s)"
    PROBE_PATH="$POSTGREST_URL/rpc/${PROBE#hivemind_endpoints.}"

    probe_sql() {
        if ! psql "$POSTGRES_URL" -v ON_ERROR_STOP=on -c "$1"; then
            echo "ERROR: Failed to run: $1"
            exit 1
        fi
    }

    # Waits until GET of the probe answers HTTP $1; after the timeout, fails saying PostgREST did not "$2"
    wait_for_probe() {
        local expected="$1" what="$2" code="" start
        start=$(date +%s)
        while true; do
            code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$PROBE_PATH" || true)
            if [ "$code" = "$expected" ]; then
                return 0
            fi
            if [ $(($(date +%s) - start)) -ge "$POSTGREST_TIMEOUT" ]; then
                echo "ERROR: PostgREST at $POSTGREST_URL did not $what within ${POSTGREST_TIMEOUT}s (last HTTP status: ${code:-none})"
                psql "$POSTGRES_URL" -c "DROP FUNCTION IF EXISTS $PROBE()" || true
                exit 1
            fi
            sleep 1
        done
    }

    echo "Waiting for PostgREST at $POSTGREST_URL to reload its schema cache..."
    probe_sql "CREATE FUNCTION $PROBE() RETURNS integer LANGUAGE sql IMMUTABLE AS 'SELECT 1'"
    notify_postgrest
    wait_for_probe 200 "reload its schema cache"
    probe_sql "DROP FUNCTION $PROBE()"
    notify_postgrest
    wait_for_probe 404 "drop the reload probe from its schema cache"
    echo "OK: PostgREST serves the reloaded functions"
fi

echo ""
echo "=== PostgREST functions reloaded successfully ==="
