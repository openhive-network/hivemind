#!/bin/bash
# Check Hivemind pipeline status efficiently for Claude
# Usage: check-hivemind-pipeline.sh [pipeline_id|branch]
# Output: Concise report on pipeline problems
#
# Key jobs to watch:
#   - prepare_haf_image, prepare_haf_data: HAF infrastructure
#   - replay_data_copy: Copies HAF data for pipeline, uses NFS cache
#   - prepare_hivemind_image: Builds hivemind docker image
#   - sync: Runs hivemind sync to block 5M (includes reputation_tracker)
#   - e2e_benchmark_on_postgrest: All API smoketests (13+ test suites)

set -eo pipefail

PROJECT_ID=213
PROJECT_NAME="hivemind"
BRANCH="${1:-feature/nfs-cache-manager}"

# If arg looks like a number, treat as pipeline ID
if [[ "$BRANCH" =~ ^[0-9]+$ ]]; then
    PID="$BRANCH"
else
    # Get latest pipeline for branch
    PID=$(glab api "projects/$PROJECT_ID/pipelines?ref=$BRANCH&per_page=1" 2>/dev/null | jq -r '.[0].id')
fi

if [[ -z "$PID" || "$PID" == "null" ]]; then
    echo "ERROR: No pipeline found for $BRANCH"
    exit 1
fi

# Get pipeline info
PIPELINE=$(glab api "projects/$PROJECT_ID/pipelines/$PID" 2>/dev/null)
STATUS=$(echo "$PIPELINE" | jq -r '.status')
SHA=$(echo "$PIPELINE" | jq -r '.sha[:8]')
CREATED=$(echo "$PIPELINE" | jq -r '.created_at[:16]' | tr 'T' ' ')

echo "Pipeline $PID ($BRANCH) - $STATUS"
echo "SHA: $SHA | Created: $CREATED"
echo "URL: https://gitlab.syncad.com/hive/$PROJECT_NAME/-/pipelines/$PID"
echo ""

# Get all jobs
JOBS=$(glab api "projects/$PROJECT_ID/pipelines/$PID/jobs?per_page=100" 2>/dev/null)

# Job summary by stage
echo "=== Summary ==="
echo "$JOBS" | jq -r 'group_by(.status) | .[] | "\(.[0].status): \(length)"' | sort
echo ""

# Key jobs status
echo "=== Key Jobs ==="
echo "$JOBS" | jq -r '
  .[] | select(.name == "prepare_haf_image" or .name == "prepare_haf_data" or
               .name == "replay_data_copy" or .name == "prepare_hivemind_image" or
               .name == "sync" or .name == "e2e_benchmark_on_postgrest") |
  "\(.status | if . == "success" then "OK" elif . == "failed" then "FAIL" elif . == "running" then "RUN" else . end) \(.name)"
'
echo ""

# Failed jobs with details
FAILED=$(echo "$JOBS" | jq -r '.[] | select(.status == "failed")')
if [[ -n "$FAILED" && "$FAILED" != "null" ]]; then
    echo "=== FAILED JOBS ==="
    echo "$JOBS" | jq -r '.[] | select(.status == "failed") | "[\(.id)] \(.name) (stage: \(.stage))"'
    echo ""

    # Get logs from each failed job (extract key errors)
    for JOB_ID in $(echo "$JOBS" | jq -r '.[] | select(.status == "failed") | .id'); do
        JOB_NAME=$(echo "$JOBS" | jq -r ".[] | select(.id == $JOB_ID) | .name")
        echo "--- $JOB_NAME (job $JOB_ID) ---"

        # Get job log
        LOG=$(glab api "projects/$PROJECT_ID/jobs/$JOB_ID/trace" 2>/dev/null | tail -150)

        # Extract relevant error patterns based on job type
        case "$JOB_NAME" in
            sync)
                # Look for hivemind sync errors, postgres errors, timeout
                echo "$LOG" | grep -E -A3 -B2 "Error|Exception|FATAL|could not connect|timeout|Traceback" | head -50
                ;;
            e2e_benchmark_on_postgrest)
                # Look for test failures - pytest output
                echo "$LOG" | grep -E -A2 -B1 "FAILED|ERROR|AssertionError|passed.*failed" | head -50
                ;;
            prepare_haf_*)
                # Docker/registry/cache errors
                echo "$LOG" | grep -E -A3 -B2 "error|failed|Could not|timeout|denied" | head -40
                ;;
            replay_data_copy)
                # NFS cache issues, copy failures
                echo "$LOG" | grep -E -A3 -B2 "ERROR|Failed|No such file|Permission denied|cache" | head -40
                ;;
            *)
                # Generic error extraction
                if echo "$LOG" | grep -qE "FAILED|Error|Exception|Traceback"; then
                    echo "$LOG" | grep -E -A5 -B2 "FAILED|Error:|Exception:|Traceback" | head -40
                else
                    echo "$LOG" | tail -30
                fi
                ;;
        esac
        echo ""
    done
fi

# Running jobs
RUNNING=$(echo "$JOBS" | jq -r '.[] | select(.status == "running")')
if [[ -n "$RUNNING" && "$RUNNING" != "null" ]]; then
    echo "=== RUNNING ==="
    echo "$JOBS" | jq -r '.[] | select(.status == "running") | "\(.name) on \(.runner.description // "pending")"'
    echo ""
fi

# Canceled jobs
CANCELED=$(echo "$JOBS" | jq -r '.[] | select(.status == "canceled")')
if [[ -n "$CANCELED" && "$CANCELED" != "null" ]]; then
    echo "=== CANCELED ==="
    echo "$JOBS" | jq -r '.[] | select(.status == "canceled") | .name'
    echo ""
fi

# Test summary if e2e job completed
E2E_JOB=$(echo "$JOBS" | jq -r '.[] | select(.name == "e2e_benchmark_on_postgrest" and .status == "success")')
if [[ -n "$E2E_JOB" && "$E2E_JOB" != "null" ]]; then
    echo "=== TEST SUITES (e2e_benchmark_on_postgrest) ==="
    echo "Tests: bridge_api, condenser_api, database_api, follow_api, tags_api,"
    echo "       hive_api, search-api, rest_api, postgrest_negative, mock_tests"
    echo "(all positive and negative variants)"
fi

# If pipeline succeeded
if [[ "$STATUS" == "success" ]]; then
    echo "Pipeline PASSED - all jobs successful"
fi
