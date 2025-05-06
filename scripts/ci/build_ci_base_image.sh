#! /bin/bash

set -e

print_help () {
cat <<EOF
  Usage: $0 [OPTION[=VALUE]]...

  Script for building runtime and base Hivemind Docker images.
  
  Options:
    --registry=URL Registry to use as a part of image names (default: registry.gitlab.syncad.com/hive/hivemind)
    --tag=TAG      Image tag (default: python-3.12-slim-1)
EOF
}

function image-exists() {
  local image=$1
  docker manifest inspect "$image" > /dev/null
  return $?
}

REGISTRY=${REGISTRY:-"registry.gitlab.syncad.com/hive/hivemind"}
CI_IMAGE_TAG=${CI_IMAGE_TAG:-"python-3.12-slim-1"}

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h|-?)
      print_help
      exit 0
      ;;
    --registry=*)
      REGISTRY="${1#*=}"
      ;;
    --tag=*)
      CI_IMAGE_TAG="${1#*=}"
      ;;
    *)
      echo -e "  ERROR: '$1' is not a valid option/positional argument\n"
      print_help
      exit 1
    ;;
    esac
    shift
done

BUILD_OPTIONS=(
  "--platform=linux/amd64" 
  "--progress=plain"
  )

if [[ -n "${REGISTRY}" ]]; then
  BUILD_OPTIONS+=("--build-arg")
  BUILD_OPTIONS+=("CI_REGISTRY_IMAGE=$REGISTRY/") 
fi

if [[ -n "${CI_IMAGE_TAG}" ]]; then
  BUILD_OPTIONS+=("--build-arg")
  BUILD_OPTIONS+=("CI_IMAGE_TAG=:$CI_IMAGE_TAG") 
fi

# On CI push the images to the registry, outside of CI add
# them to `docker images`
if [[ -n "${CI:-}" ]]; then
  BUILD_OPTIONS+=("--push")
else
  BUILD_OPTIONS+=("--load")
fi

RUNTIME_TAG="${REGISTRY}/runtime:${CI_IMAGE_TAG}"
CI_BASE_IMAGE_TAG="${REGISTRY}/ci-base-image:${CI_IMAGE_TAG}"

# Skip building images on CI if they already exist in the repository 
if [[ -n "${CI:-}" ]] && image-exists "$RUNTIME_TAG"; then
  echo "Image $RUNTIME_TAG already exists. Skipping build..."
else
  docker buildx build "${BUILD_OPTIONS[@]}" \
    --target=runtime \
    --tag "$RUNTIME_TAG" \
    --file Dockerfile .
fi

if [[ -n "${CI:-}" ]] && image-exists "$CI_BASE_IMAGE_TAG"; then
  echo "Image $CI_BASE_IMAGE_TAG already exists. Skipping build..."
else
  # On CI explicitly use the runtiume image to build the ci-base image, locally just use
  # the build cache to get the same result
  if [[ -n "${CI:-}" ]]; then
    BUILD_OPTIONS+=("--build-context")
    BUILD_OPTIONS+=("runtime=docker-image://${RUNTIME_TAG}")
  fi
  docker buildx build "${BUILD_OPTIONS[@]}" \
    --target=ci-base-image \
    --tag "$CI_BASE_IMAGE_TAG" \
    --file Dockerfile .
fi




