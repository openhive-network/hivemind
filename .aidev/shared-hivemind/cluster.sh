#!/usr/bin/env bash
# One-shot `cluster` service of the shared hivemind (.aidev/shared-hivemind.compose.yml),
# run in the hive/haf/fixture-5m image of HAF_FIXTURE_COMMIT before `hivemind` starts.
# hive/haf's .aidev/shared-haf/seed.sh, for this service's own data root.
#
# 1. Refuses a data root that is not ZFS: the per-run clones are only
#    copy-on-write there (file_copy_method = clone needs block cloning).
# 2. Copies the image's replayed cluster once per HAF commit to
#    <root>/<commit>/haf_db_store (through <commit>.partial, so an interrupted
#    copy is never served); exits 0 without copying when it is already there.
#    The hivemind templates of every schema revision live in that cluster.
#
# Environment: HAF_FIXTURE_COMMIT (40-hex commit of the image), HIVEMIND_SHARED_ROOT
# (the ZFS dataset mounted into the container).
set -euo pipefail

commit="${HAF_FIXTURE_COMMIT:?HAF_FIXTURE_COMMIT must name the fixture image commit}"
root="${HIVEMIND_SHARED_ROOT:?HIVEMIND_SHARED_ROOT must name the mounted ZFS dataset}"
image_store=/home/hived/datadir/haf_db_store

if [[ ! "$commit" =~ ^[0-9a-f]{40}$ ]]; then
    echo "HAF_FIXTURE_COMMIT must be a full 40-character commit SHA, got '$commit'" >&2
    exit 1
fi
fs="$(stat -f -c %T "$root")"
if [ "$fs" != zfs ]; then
    echo "$root is $fs, not ZFS: clones would be full copies; mount a ZFS dataset with block cloning there" >&2
    exit 1
fi

store="$root/$commit/haf_db_store"
if sudo -n test -f "$store/pgdata/PG_VERSION"; then
    echo "$root/$commit is already seeded"
    exit 0
fi

# The daemon creates a missing bind source as an empty directory; such a
# leftover holds nothing to keep.
sudo -n rmdir "$store" "$root/$commit" 2>/dev/null || true
if sudo -n test -e "$root/$commit"; then
    echo "$root/$commit exists but holds no cluster; remove it to seed again" >&2
    exit 1
fi
if [ -L "$image_store" ] || ! sudo -n test -f "$image_store/pgdata/PG_VERSION"; then
    echo "this image has no replayed cluster at $image_store to seed from" >&2
    exit 1
fi
echo "copying the image's cluster to $root/$commit"
sudo -n rm -rf "$root/$commit.partial"
sudo -n mkdir -p "$root/$commit.partial"
sudo -n cp -a "$image_store" "$root/$commit.partial/"
sudo -n mv "$root/$commit.partial" "$root/$commit"
