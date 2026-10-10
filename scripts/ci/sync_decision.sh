#!/bin/bash
#
# Decides how CI gets synced data for the commits in <base>..<head>, and prints
# the result as dotenv lines on stdout:
#
#   AUTO_SKIP_SYNC=true|false
#   POSTGREST_ONLY_CHANGE=true|false
#
# Every decision is logged on stderr.
#
#   AUTO_SKIP_SYNC=<pattern result> HAF_APP_SKIP_PATTERNS=<regex> \
#   POSTGREST_ONLY_PATTERNS=<regex> CI_COMMIT_REF_NAME=<ref> \
#     sync_decision.sh <base> [<head>]
#
# AUTO_SKIP_SYNC is the path-based result of .haf_app_detect_changes. Commits can
# declare `Hivemind-Sync: required|not-required` (see CLAUDE.md, "CI sync
# decision"):
#   - any `required` forces a full sync;
#   - a file every changing commit of which says `not-required` no longer
#     counts against POSTGREST_ONLY_CHANGE, unless it matches GUARD_PATTERNS.
# On develop and master `not-required` is ignored, so a wrong skip surfaces on
# the first post-merge pipeline. Commits without the trailer, and merges, are
# classified by path alone.

set -euo pipefail

base="${1:?usage: $0 <base> [<head>]}"
head_rev="${2:-HEAD}"
skip_patterns="${HAF_APP_SKIP_PATTERNS:?HAF_APP_SKIP_PATTERNS must be set}"
postgrest_patterns="${POSTGREST_ONLY_PATTERNS:?POSTGREST_ONLY_PATTERNS must be set}"
auto_skip="${AUTO_SKIP_SYNC:-false}"
ref="${CI_COMMIT_REF_NAME:-}"

GUARD_PATTERNS='^hive/indexer/|^hive/db/sql_scripts/(schema|upgrade)/|massive_sync\.sql$|^scripts/install_app\.sql$|^scripts/setup_postgres\.sh$'

log() { echo "$*" >&2; }

decide() {
  log "=== Sync decision: AUTO_SKIP_SYNC=$1 POSTGREST_ONLY_CHANGE=$2 ==="
  echo "AUTO_SKIP_SYNC=$1"
  echo "POSTGREST_ONLY_CHANGE=$2"
  exit 0
}

commit_files() {
  git diff-tree --no-commit-id --name-only --no-renames -r "$1"
}

honour_not_required=true
if [[ "$ref" == "develop" || "$ref" == "master" ]]; then
  honour_not_required=false
  log "Ref $ref: Hivemind-Sync: not-required is ignored"
fi

any_required=false
declare -A trusted=() distrusted=()
while IFS=$'\t' read -r sha parents trailers; do
  claims_required=false claims_not_required=false
  # Each value is "<decision> — <reason>" (aidev#15385): the decision is its first word.
  IFS=',' read -ra values <<< "$(tr '[:upper:]' '[:lower:]' <<< "$trailers")"
  for v in "${values[@]}"; do
    read -r v _ <<< "$v"
    case "$v" in
      required) claims_required=true ;;
      not-required) claims_not_required=true ;;
      '') ;;
      *) log "Commit ${sha:0:8}: unknown Hivemind-Sync value '$v' ignored" ;;
    esac
  done

  if $claims_required; then
    log "Commit ${sha:0:8}: Hivemind-Sync: required"
    any_required=true
    continue
  fi
  if $claims_not_required && $honour_not_required && [[ "$parents" != *" "* ]]; then
    log "Commit ${sha:0:8}: Hivemind-Sync: not-required"
    while IFS= read -r f; do [[ -n "$f" ]] && trusted["$f"]=1; done < <(commit_files "$sha")
  else
    if $claims_not_required; then
      log "Commit ${sha:0:8}: Hivemind-Sync: not-required (not honoured here)"
    fi
    while IFS= read -r f; do [[ -n "$f" ]] && distrusted["$f"]=1; done < <(commit_files "$sha")
  fi
done < <(git log --format='%H%x09%P%x09%(trailers:key=Hivemind-Sync,valueonly,separator=%x2C)' "$base..$head_rev")

if $any_required; then
  log "A commit requires a full sync"
  decide false false
fi

if [[ "$auto_skip" == "true" ]]; then
  log "Only tests/docs changed - sync can be skipped"
  decide true false
fi

changed_files="$(git diff --name-only "$base" "$head_rev")"
needs_work="$(grep -vE "$skip_patterns" <<< "$changed_files" || true)"
if [[ -z "$needs_work" ]]; then
  decide false false
fi

non_postgrest=()
while IFS= read -r f; do
  if [[ -n "${trusted[$f]:-}" && -z "${distrusted[$f]:-}" ]]; then
    if grep -qE "$GUARD_PATTERNS" <<< "$f"; then
      log "Guard keeps $f despite Hivemind-Sync: not-required"
      non_postgrest+=("$f")
    else
      log "Hivemind-Sync: not-required drops $f"
    fi
  else
    non_postgrest+=("$f")
  fi
done < <(grep -vE "$postgrest_patterns" <<< "$needs_work" || true)

if [[ ${#non_postgrest[@]} -eq 0 ]]; then
  log "All changes that need work are PostgREST/endpoint SQL or declared not to need a sync:"
  log "$(head -20 <<< "$needs_work")"
  log "Sync can be skipped - SQL functions will be reloaded on cached data."
  decide false true
fi

log "Files requiring full sync:"
log "$(printf '%s\n' "${non_postgrest[@]}" | head -20)"
decide false false
