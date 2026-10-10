#!/bin/bash
#
# Chooses and extracts the hivemind sync cache a pipeline can use instead of a
# full sync, and prints "<mode> <key>": mode "reuse" means the cache matches this
# commit's SQL as is, "reload" that the e2e job must reload the SQL functions
# into it. Prints nothing when no cache fits, i.e. a full sync is needed.
#
#   select_sync_cache.sh auto-skip <revision> <candidate-key>...
#       The first candidate key (this commit, then docs/tests/CI-only ancestors)
#       whose cache extracts, as "reuse"; else the compatible cache, as "reload".
#
#   select_sync_cache.sh compatible <revision>
#       The newest cache for HAF_COMMIT synced with schema <revision>, as "reload"
#       (see pick_compatible_cache.sh).
#
# Reads CACHE_MANAGER, SYNC_CACHE_TYPE, HAF_COMMIT and DATA_CACHE_NFS_PREFIX from
# the environment; extracts into ${LOCAL_CACHE_ROOT:-/cache}/<type>_<key>.
# Logs to stderr.

set -euo pipefail

cache_manager="${CACHE_MANAGER:?CACHE_MANAGER must be set}"
cache_type="${SYNC_CACHE_TYPE:?SYNC_CACHE_TYPE must be set}"
haf_commit="${HAF_COMMIT:?HAF_COMMIT must be set}"
nfs_type_dir="${DATA_CACHE_NFS_PREFIX:?DATA_CACHE_NFS_PREFIX must be set}/${cache_type}"
local_root="${LOCAL_CACHE_ROOT:-/cache}"

# "quiet" drops the cache manager's error output: a miss is expected for most
# auto-skip candidates.
_extract() {
  if [[ "${2:-}" == "quiet" ]]; then
    "$cache_manager" get "$cache_type" "$1" "${local_root}/${cache_type}_$1" >&2 2>/dev/null
  else
    "$cache_manager" get "$cache_type" "$1" "${local_root}/${cache_type}_$1" >&2
  fi
}

_compatible() {
  local revision="$1" key
  echo "Searching for caches with HAF commit ${haf_commit} and schema revision ${revision:-unknown}" >&2
  key=$("$cache_manager" list "$cache_type" 2>/dev/null \
    | "$(dirname "$0")/pick_compatible_cache.sh" pick "$haf_commit" "$revision" "$nfs_type_dir" || true)
  if [[ -z "$key" ]]; then
    echo "No compatible cache for HAF commit ${haf_commit} and schema revision ${revision:-unknown}" >&2
    return 0
  fi
  echo "Attempting to use compatible cache: ${key}" >&2
  if ! _extract "$key"; then
    echo "Failed to extract compatible cache ${key}" >&2
    return 0
  fi
  echo "reload ${key}"
}

_auto_skip() {
  local revision="$1" key
  shift
  for key in "$@"; do
    if _extract "$key" quiet; then
      echo "Cache found: ${key}" >&2
      echo "reuse ${key}"
      return 0
    fi
    echo "No cache for ${key}" >&2
  done
  echo "No cache for this commit or a docs/tests/CI-only ancestor - trying a compatible cache with SQL reload" >&2
  _compatible "$revision"
}

command="${1:?usage: $0 auto-skip|compatible <revision> ...}"
shift
case "$command" in
  auto-skip) _auto_skip "${1-}" "${@:2}" ;;
  compatible) _compatible "${1-}" ;;
  *) echo "unknown command: ${command}" >&2; exit 2 ;;
esac
