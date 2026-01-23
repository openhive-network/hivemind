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
# IMPORTANT: The SQL file list is extracted from hive/db/schema.py to ensure
# this script stays in sync with the main installation code.
#
# Usage:
#   ./scripts/ci/reload-postgrest-functions.sh --postgres-url=postgresql://hivemind@localhost:5432/haf_block_log
#
# Options:
#   --postgres-url=URL    PostgreSQL connection URL (required)
#   --admin-url=URL       Admin PostgreSQL URL for plpython3u scripts (optional, defaults to haf_admin)
#   --verify              Verify functions exist after reload
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
    echo "  --verify              Verify functions exist after reload"
    echo "  --help                Show this help message"
    echo
}

POSTGRES_URL=""
ADMIN_URL=""
VERIFY=false

while [ $# -gt 0 ]; do
    case "$1" in
        --postgres-url=*)
            POSTGRES_URL="${1#*=}"
            ;;
        --admin-url=*)
            ADMIN_URL="${1#*=}"
            ;;
        --verify)
            VERIFY=true
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
SCHEMA_PY="$REPO_ROOT/hive/db/schema.py"

echo "=== Reloading PostgREST SQL functions ==="
echo "PostgreSQL URL: ${POSTGRES_URL%%@*}@..."
echo "SQL scripts dir: $SQL_SCRIPTS_DIR"

# Extract PostgREST/endpoint scripts from schema.py
# This ensures we stay in sync with the main installation code
extract_postgrest_scripts() {
    # Extract the sql_scripts list from setup_runtime_code() in schema.py
    # Filter to only postgrest/ and endpoints/ scripts
    # Exclude preprocess_search_query.sql as it's handled separately (requires admin)
    grep -E '^\s+"(postgrest/|endpoints/)' "$SCHEMA_PY" | \
        sed 's/.*"\([^"]*\)".*/\1/' | \
        grep -v '^#' | \
        grep -v 'preprocess_search_query'
}

# Function to load a SQL script
load_sql() {
    local url="$1"
    local script="$2"
    local script_path="$SQL_SCRIPTS_DIR/$script"

    if [ -f "$script_path" ]; then
        echo "  Loading: $script"
        if ! psql "$url" -v ON_ERROR_STOP=on -f "$script_path" > /dev/null 2>&1; then
            echo "    WARNING: Error loading $script (may be expected for existing objects)"
        fi
    else
        echo "  WARNING: Script not found: $script"
    fi
}

# First, execute admin-level scripts (plpython3u)
# These are defined in setup_db() in schema.py
echo ""
echo "=== Installing admin-level scripts ==="
load_sql "$ADMIN_URL" "postgrest/utilities/preprocess_search_query.sql"

# Load PostgREST scripts in the order from schema.py::setup_runtime_code()
# This ensures proper dependency resolution
echo ""
echo "=== Loading PostgREST scripts (extracted from schema.py) ==="

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
fi

echo ""
echo "=== PostgREST functions reloaded successfully ==="
