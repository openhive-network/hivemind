#!/bin/bash
#
# Schema-revision bookkeeping for hivemind sync caches on NFS, so a cache is
# reused only by a commit whose schema it was synced with.
#
#   pick_compatible_cache.sh revision <update_db_patchlevel.sql>
#       Prints the schema revision the patch-level script installs (empty if none).
#
#   pick_compatible_cache.sh record <update_db_patchlevel.sql> <nfs-type-dir> <key>
#       Records that revision for the cache <nfs-type-dir>/<key>.tar, next to
#       cache-manager's <nfs-type-dir>/<key>/.metadata (removed with it on cleanup).
#
#   cache-manager.sh list <type> | pick_compatible_cache.sh pick <haf-commit> <revision> <nfs-type-dir>
#       Prints the key of the newest cache for <haf-commit> recorded with <revision>,
#       newest by cache-manager's .metadata created_at (the tar's mtime without one).
#       Prints nothing when no cache matches; caches with no recorded revision never
#       match. Logs every candidate it skips, and the choice, to stderr.

set -euo pipefail

_REVISION_FILE=".hivemind_revision"

_revision() {
  grep -oP "'\K[a-f0-9]{40}(?=')" "$1" | tail -1 || true
}

_record() {
  local patchlevel_file="$1" dir="$2" key="$3" revision
  revision=$(_revision "$patchlevel_file")
  if [[ -z "$revision" ]]; then
    echo "No schema revision in ${patchlevel_file}: ${key} stays unrecorded" >&2
    return 1
  fi
  mkdir -p "${dir}/${key}"
  echo "$revision" > "${dir}/${key}/${_REVISION_FILE}"
  echo "Recorded schema revision ${revision} for cache ${key}" >&2
}

_created_epoch() {
  local dir="$1" key="$2" created
  created=$(sed -n 's/.*"created_at": *"\([^"]*\)".*/\1/p' "${dir}/${key}/.metadata" 2>/dev/null | head -1 || true)
  if [[ -n "$created" ]] && date -d "$created" +%s 2>/dev/null; then
    return 0
  fi
  stat -c %Y "${dir}/${key}.tar" 2>/dev/null || echo 0
}

_pick() {
  local haf_commit="$1" expected="$2" dir="$3"
  local key revision epoch best="" best_epoch=-1 age

  if [[ -z "$expected" ]]; then
    echo "No expected schema revision: no cache can be shown compatible" >&2
    return 0
  fi

  # cache-manager list prints "  <key> - <size> - <date>" under section headers.
  while read -r key _; do
    [[ "$key" == "${haf_commit}_"* ]] || continue
    revision=$(tr -d '[:space:]' < "${dir}/${key}/${_REVISION_FILE}" 2>/dev/null || true)
    if [[ "$revision" != "$expected" ]]; then
      echo "Skipping ${key}: schema revision ${revision:-unrecorded}, need ${expected}" >&2
      continue
    fi
    epoch=$(_created_epoch "$dir" "$key")
    if (( epoch > best_epoch )); then
      best="$key"
      best_epoch="$epoch"
    fi
  done

  if [[ -z "$best" ]]; then
    echo "No cache for HAF commit ${haf_commit} has schema revision ${expected}" >&2
    return 0
  fi
  age=$(( $(date +%s) - best_epoch ))
  echo "Chosen cache ${best}: schema revision ${expected}, created $(date -u -d "@${best_epoch}" +%Y-%m-%dT%H:%M:%SZ), age $(( age / 3600 ))h$(( age % 3600 / 60 ))m" >&2
  echo "$best"
}

command="${1:?usage: $0 revision|record|pick ...}"
shift
case "$command" in
  revision) _revision "${1:?patch-level file required}" ;;
  record) _record "${1:?patch-level file required}" "${2:?NFS cache type dir required}" "${3:?cache key required}" ;;
  pick) _pick "${1:?HAF commit required}" "${2-}" "${3:?NFS cache type dir required}" ;;
  *) echo "unknown command: ${command}" >&2; exit 2 ;;
esac
