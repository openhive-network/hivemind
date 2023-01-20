#! /bin/bash

[[ -z "$DOCKER_HUB_USER" ]] && echo "Variable DOCKER_HUB_USER must be set" && exit 1
[[ -z "$DOCKER_HUB_PASSWORD" ]] && echo "Variable DOCKER_HUB_PASSWORD must be set" && exit 1

set -e

docker login -u "$CI_REGISTRY_USER" -p "$CI_REGISTRY_PASSWORD" "$CI_REGISTRY"
#docker login -u "$DOCKER_HUB_USER" -p "$DOCKER_HUB_PASSWORD"

pushd "$CI_PROJECT_DIR"

# Turn PEP 440-compliant version number into a Docker-compliant tag
#shellcheck disable=SC2001
TAG=$(echo "$CI_COMMIT_TAG" | sed 's/[!+]/-/g')

docker buildx build --platform=amd64 --progress=plain --target=instance \
  --build-arg CI_REGISTRY_IMAGE="$CI_REGISTRY_IMAGE/" \
  --tag "${CI_REGISTRY_IMAGE}/instance:instance-${TAG}" \
  --tag "hiveio/hive:${TAG}" \
  --file Dockerfile .

docker push "${CI_REGISTRY_IMAGE}/instance:instance-${TAG}"
#docker push "hiveio/hive:${TAG}"

popd