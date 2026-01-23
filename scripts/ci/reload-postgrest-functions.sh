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
# IMPORTANT: The order of SQL files matches hive/db/schema.py::setup_runtime_code()
# to ensure proper dependency resolution.
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

echo "=== Reloading PostgREST SQL functions ==="
echo "PostgreSQL URL: ${POSTGRES_URL%%@*}@..."
echo "SQL scripts dir: $SQL_SCRIPTS_DIR"

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
echo ""
echo "=== Installing admin-level scripts ==="
load_sql "$ADMIN_URL" "postgrest/utilities/preprocess_search_query.sql"

# Load PostgREST scripts in the exact order from schema.py::setup_runtime_code()
# This ensures proper dependency resolution
echo ""
echo "=== Loading PostgREST scripts (in dependency order from schema.py) ==="

# Order matches hive/db/schema.py lines 656-749
POSTGREST_SCRIPTS=(
    # Main PostgREST entry point
    "postgrest/home.sql"
    # Utilities (base dependencies first)
    "postgrest/utilities/exceptions.sql"
    "postgrest/utilities/validate_json_arguments.sql"
    "postgrest/utilities/api_limits.sql"
    "postgrest/utilities/parse_argument_from_json.sql"
    "postgrest/utilities/valid_account.sql"
    "postgrest/utilities/find_account_id.sql"
    # condenser_api.get_follow_count (depends on find_account_id)
    "postgrest/condenser_api/condenser_api_get_follow_count.sql"
    # More utilities
    "postgrest/utilities/find_comment_id.sql"
    "postgrest/utilities/valid_permlink.sql"
    # condenser_api.get_reblogged_by (depends on find_comment_id, valid_permlink)
    "postgrest/condenser_api/condenser_api_get_reblogged_by.sql"
    # More utilities
    "postgrest/utilities/valid_number.sql"
    "postgrest/utilities/valid_tag.sql"
    "postgrest/utilities/find_category_id.sql"
    # condenser_api tag functions
    "postgrest/condenser_api/condenser_api_get_trending_tags.sql"
    "postgrest/condenser_api/condenser_api_get_account_reputations.sql"
    # Community utilities
    "postgrest/utilities/check_community.sql"
    "postgrest/utilities/valid_community.sql"
    "postgrest/utilities/valid_limit.sql"
    "postgrest/utilities/json_date.sql"
    "postgrest/utilities/community.sql"
    # bridge_api community functions
    "postgrest/bridge_api/bridge_api_get_community.sql"
    "postgrest/bridge_api/bridge_api_get_community_context.sql"
    # Dispatch and API method utilities
    "postgrest/utilities/dispatch.sql"
    "postgrest/utilities/get_api_method.sql"
    "postgrest/utilities/valid_offset.sql"
    "postgrest/utilities/list_votes.sql"
    "postgrest/utilities/assets_operations.sql"
    "postgrest/utilities/create_condenser_post_object.sql"
    # condenser_api blog and content functions
    "postgrest/condenser_api/condenser_api_get_blog.sql"
    "postgrest/condenser_api/condenser_api_get_content.sql"
    # database_api vote functions
    "postgrest/database_api/database_api_find_votes.sql"
    "postgrest/database_api/database_api_list_votes.sql"
    # condenser_api active votes
    "postgrest/condenser_api/condenser_api_get_active_votes.sql"
    # Post object utilities
    "postgrest/utilities/rep_log10.sql"
    "postgrest/utilities/muted_reasons_operations.sql"
    "postgrest/utilities/create_bridge_post_object.sql"
    # bridge_api post functions
    "postgrest/bridge_api/bridge_api_get_post.sql"
    "postgrest/bridge_api/bridge_api_get_payout_stats.sql"
    # hive_api info functions
    "postgrest/hive_api/hive_api_get_info.sql"
    "postgrest/hive_api/hive_api_db_head_state.sql"
    # Account posts utilities and functions
    "postgrest/utilities/get_account_posts.sql"
    "postgrest/bridge_api/bridge_api_get_account_posts.sql"
    "postgrest/bridge_api/bridge_api_get_relationship_between_accounts.sql"
    "postgrest/bridge_api/bridge_api_unread_notifications.sql"
    # Ranked posts utilities and functions
    "postgrest/utilities/find_tag_id.sql"
    "postgrest/utilities/get_ranked_posts.sql"
    "postgrest/utilities/get_reblogged_posts.sql"
    "postgrest/bridge_api/bridge_api_get_ranked_posts.sql"
    # condenser_api discussion functions
    "postgrest/condenser_api/condenser_api_get_discussions_by_blog_or_feed.sql"
    "postgrest/condenser_api/condenser_api_get_discussions_by_comments.sql"
    "postgrest/condenser_api/condenser_api_get_replies_by_last_update.sql"
    "postgrest/condenser_api/condenser_api_get_discussion_by_author_before_date.sql"
    "postgrest/condenser_api/condenser_api_get_discussion_by.sql"
    # Notifications utilities and functions
    "postgrest/utilities/notifications.sql"
    "postgrest/bridge_api/bridge_api_account_notifications.sql"
    "postgrest/bridge_api/bridge_api_post_notifications.sql"
    # database_api comments
    "postgrest/utilities/create_database_post_object.sql"
    "postgrest/database_api/database_api_find_comments.sql"
    # Date validation
    "postgrest/utilities/valid_date.sql"
    # bridge_api list and community functions
    "postgrest/bridge_api/bridge_api_list_subscribers.sql"
    "postgrest/bridge_api/bridge_api_get_trending_topics.sql"
    "postgrest/bridge_api/bridge_api_list_communities.sql"
    "postgrest/bridge_api/bridge_api_get_discussion.sql"
    "postgrest/bridge_api/bridge_api_get_post_header.sql"
    # Profile utilities and functions
    "postgrest/utilities/get_profiles.sql"
    "postgrest/utilities/get_muted_accounts_list.sql"
    "postgrest/bridge_api/bridge_api_get_profile.sql"
    "postgrest/bridge_api/bridge_api_does_user_follow_any_lists.sql"
    "postgrest/utilities/extract_profile_metadata.sql"
    "postgrest/bridge_api/bridge_api_get_follow_list.sql"
    # Role and community functions
    "postgrest/utilities/get_role_name.sql"
    "postgrest/utilities/find_community_id.sql"
    "postgrest/bridge_api/bridge_api_list_community_roles.sql"
    "postgrest/bridge_api/bridge_api_list_all_subscriptions.sql"
    "postgrest/bridge_api/bridge_api_list_pop_communities.sql"
    # condenser_api follow functions
    "postgrest/condenser_api/extract_parameters_for_get_following_and_followers.sql"
    "postgrest/condenser_api/condenser_api_get_followers.sql"
    "postgrest/condenser_api/condenser_api_get_following.sql"
    # Remaining utilities
    "postgrest/utilities/find_subscription_id.sql"
    "postgrest/bridge_api/bridge_api_get_profiles.sql"
    "postgrest/utilities/valid_accounts.sql"
    # Search API
    "postgrest/search-api/find_text.sql"
)

for script in "${POSTGREST_SCRIPTS[@]}"; do
    load_sql "$POSTGRES_URL" "$script"
done

# Endpoint scripts (REST-style endpoints)
echo ""
echo "=== Loading endpoint scripts ==="
ENDPOINT_SCRIPTS=(
    "endpoints/endpoint_schema.sql"
    "endpoints/types/operation.sql"
    "endpoints/accounts/get_ops_by_account.sql"
    "endpoints/blog/get_reblogs.sql"
)

for script in "${ENDPOINT_SCRIPTS[@]}"; do
    load_sql "$POSTGRES_URL" "$script"
done

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
