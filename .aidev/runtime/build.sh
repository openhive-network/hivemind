#!/usr/bin/env bash
# Build (and with --push, publish) .aidev/runtime/Dockerfile on the image
# .aidev/project.yaml's followed base names now, and print the digest-pinned reference.
# AIDEV builds the suites' runtime itself; this script is for the shared hivemind's
# seeder (`sandbox.shared.hivemind.env.HIVEMIND_RUNTIME_IMAGE`). See .aidev/README.md.
#
# The tag is `aidev-<hash>`, the hash of the image inputs (the base's digest, the
# Dockerfile and setup.cfg, whose install_requires it bakes in); the registry cleanup
# policy keeps `aidev-*` tags. When <repository>:aidev-<hash> is already in the
# registry nothing is built: the script prints that image's digest.
#
#   .aidev/runtime/build.sh           # registry digest, or build locally and print the local tag
#   .aidev/runtime/build.sh --push    # registry digest, or build + push and print repo@sha256:<digest>
#   .aidev/runtime/build.sh --tag     # print the input-hash tag only
set -euo pipefail

cd "$(dirname "$0")/../.."

REPOSITORY="${AIDEV_RUNTIME_REPOSITORY:-registry.gitlab.syncad.com/hive/hivemind/aidev-tests}"
BASE="$(sed -n 's/^  base: {image: "\([^"]*\)".*/\1/p' .aidev/project.yaml)"

case "${1:-}" in
    ""|--push|--tag) ;;
    *) echo "usage: $0 [--push|--tag]" >&2; exit 2 ;;
esac

# Digest of a registry reference, empty when it doesn't exist.
registry_digest() {
    docker buildx imagetools inspect "$1" --format '{{json .Manifest}}' 2>/dev/null \
        | grep -o '"digest": *"sha256:[0-9a-f]*"' | head -1 | grep -o 'sha256:[0-9a-f]*' || true
}

base_digest="$(registry_digest "${BASE:?no environment.base image in .aidev/project.yaml}")"
BASE_IMAGE="${BASE%:*}@${base_digest:?cannot resolve $BASE}"

# The Dockerfile copies setup.cfg and nothing else from the tree.
input_hash() {
    { echo "$BASE_IMAGE"; sha256sum .aidev/runtime/Dockerfile setup.cfg; } | sha256sum | cut -c1-16
}
TAG="aidev-$(input_hash)"
if [ "${1:-}" = "--tag" ]; then echo "$TAG"; exit 0; fi

digest="$(registry_digest "$REPOSITORY:$TAG")"
if [ -n "$digest" ]; then
    echo "$REPOSITORY:$TAG exists in the registry; not building" >&2
    echo "$REPOSITORY@$digest"
    exit 0
fi
echo "$REPOSITORY:$TAG is not in the registry; building it" >&2

# The context is setup.cfg alone.
context="$(mktemp -d)"
trap 'rm -rf "$context"' EXIT
cp setup.cfg "$context/"

# Optionally build through a pull-through registry cache near the build host, so FROM
# stays canonical and the build doesn't compete for the uplink. Set
# AIDEV_IMAGE_CACHE_BY_REGION to region=host:port pairs (comma-separated); a pair
# applies when its region is one of the labels of this host's FQDN, and a `*` pair
# applies to any other host. Unset (the default), the image is built straight from
# registry.gitlab.syncad.com. Prints the builder name, or nothing when no cache applies.
region_builder() {
    local cache_map="${AIDEV_IMAGE_CACHE_BY_REGION:-}"
    local region="*" label entry cache="" builder config
    [ -n "$cache_map" ] || return 0
    for label in $( (hostname -f 2>/dev/null || hostname) | tr 'A-Z.' 'a-z '); do
        for entry in ${cache_map//,/ }; do
            if [ "${entry%%=*}" = "$label" ]; then region="$label"; fi
        done
    done
    for entry in ${cache_map//,/ }; do
        if [ "${entry%%=*}" = "$region" ]; then cache="${entry#*=}"; fi
    done
    if [ -z "$cache" ]; then
        echo "no image cache applies to this host; building straight from registry.gitlab.syncad.com" >&2
        return
    fi
    builder="aidev-region-build-${cache//[.:]/-}"
    if ! docker buildx inspect "$builder" >/dev/null 2>&1; then
        config="$(mktemp)"
        printf '[registry."%s"]\n  mirrors = ["%s"]\n\n[registry."%s"]\n  http = true\n  insecure = true\n' \
            "registry.gitlab.syncad.com" "$cache" "$cache" >"$config"
        docker buildx create --name "$builder" --driver docker-container --config "$config" >/dev/null
        rm -f "$config"
    fi
    echo "$builder"
}
builder="$(region_builder)"

# The base is digest-pinned, so no --pull. No provenance, so the pushed digest is a
# plain image manifest.
build=(docker buildx build ${builder:+--builder "$builder"} --provenance=false --build-arg "BASE_IMAGE=$BASE_IMAGE"
    -f .aidev/runtime/Dockerfile -t "$REPOSITORY:$TAG")
if [ "${1:-}" != "--push" ]; then
    "${build[@]}" --load "$context" >&2
    echo "$REPOSITORY:$TAG"
    exit 0
fi

"${build[@]}" --push --metadata-file "$context/metadata.json" "$context" >&2
digest="$(grep -o '"containerimage.digest": *"sha256:[0-9a-f]*"' "$context/metadata.json" | grep -o 'sha256:[0-9a-f]*')"
echo "$REPOSITORY@${digest:?no digest in buildx metadata}"
