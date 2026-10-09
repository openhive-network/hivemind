#!/bin/bash
#
# Prints the short (8-char, as CI_COMMIT_SHORT_SHA) SHAs of the first-parent
# ancestors of a commit whose sync cache it can reuse, nearest first: those
# whose diff to the commit touches only files matching HAF_APP_SKIP_PATTERNS
# (an extended regex). Stops at the first ancestor whose diff touches anything
# else, since that and every older ancestor has a different schema or indexer.
#
#   HAF_APP_SKIP_PATTERNS=<regex> find_skip_cache_ancestor.sh [<commit> [<max-count>]]
#
# <commit> defaults to HEAD, <max-count> to 25. Runs in the current git repository.

set -euo pipefail

patterns="${HAF_APP_SKIP_PATTERNS:?HAF_APP_SKIP_PATTERNS must be set}"
head_rev="${1:-HEAD}"
max_count="${2:-25}"

# A root commit has no ancestor to reuse.
git rev-parse --verify --quiet "${head_rev}~1" >/dev/null || exit 0

for ancestor in $(git rev-list --first-parent -n "$max_count" "${head_rev}~1"); do
  if git diff --name-only "$ancestor" "$head_rev" | grep -qvE "$patterns"; then
    break
  fi
  echo "${ancestor:0:8}"
done
